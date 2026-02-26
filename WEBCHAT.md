# Hana Webchat Widget

Embeddable React widget for adding Hana AI assistant to your website.

## Quick Start

### Installation

```bash
# From the apps/webchat directory
pnpm install
pnpm build
```

### Basic Usage

```tsx
import { HanaWidget } from "@openclaw/webchat";

function App() {
  return (
    <div>
      <h1>Your Website</h1>
      {/* Widget appears as floating button in bottom-right corner */}
      <HanaWidget
        gatewayUrl="wss://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/ws/chat"
        title="Hana Assistant"
        greeting="Hi! I'm Hana. How can I help you today?"
      />
    </div>
  );
}
```

## Configuration

### HanaWidgetConfig Props

| Prop                 | Type                                | Default             | Description                             |
| -------------------- | ----------------------------------- | ------------------- | --------------------------------------- |
| `gatewayUrl`         | `string`                            | **required**        | WebSocket URL of the Hana gateway       |
| `sessionKey`         | `string`                            | auto-generated      | Session key for conversation continuity |
| `userId`             | `string`                            | -                   | User identifier (for analytics/logging) |
| `greeting`           | `string`                            | "Hi! I'm Hana..."   | Initial greeting message                |
| `title`              | `string`                            | "Hana Assistant"    | Widget header title                     |
| `placeholder`        | `string`                            | "Type a message..." | Input field placeholder                 |
| `position`           | `"bottom-right"` \| `"bottom-left"` | `"bottom-right"`    | Widget button position                  |
| `theme`              | `HanaWidgetTheme`                   | see below           | Theme customization                     |
| `onConnectionChange` | `(connected: boolean) => void`      | -                   | Connection state callback               |
| `onError`            | `(error: Error) => void`            | -                   | Error callback                          |

### Theme Customization

```tsx
<HanaWidget
  gatewayUrl="wss://..."
  theme={{
    primaryColor: "#6366f1", // Button and user message color
    backgroundColor: "#ffffff", // Chat window background
    textColor: "#1f2937", // Text color
    borderRadius: "12px", // Widget border radius
  }}
/>
```

## Integration with Hom Website (Next.js)

### 1. Install the Widget

Copy the `apps/webchat` directory to your project or publish to npm:

```bash
# Option A: Copy directly
cp -r path/to/openclaw/apps/webchat ./packages/webchat

# Option B: Symlink for development
ln -s path/to/openclaw/apps/webchat ./packages/webchat
```

### 2. Add to Next.js Layout

```tsx
// app/layout.tsx
import { HanaWidget } from "@openclaw/webchat";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>
        {children}
        <HanaWidget
          gatewayUrl={process.env.NEXT_PUBLIC_HANA_WS_URL!}
          title="Ask Hana"
          position="bottom-right"
        />
      </body>
    </html>
  );
}
```

### 3. Environment Variables

```bash
# .env.local
NEXT_PUBLIC_HANA_WS_URL=wss://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/ws/chat
```

## Trusted-Proxy Authentication

For secure embedding where the host website authenticates users, use trusted-proxy mode.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hom Website (Next.js)                         │
│  - Authenticates users (e.g., Auth0, NextAuth)                  │
│  - Sets X-Forwarded-User header in WebSocket requests           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼ WebSocket + X-Forwarded-User
┌─────────────────────────────────────────────────────────────────┐
│                    AWS ALB (hana-dev-alb)                        │
│  - Routes /ws/* to WebSocket target group                       │
│  - Maintains sticky sessions via lb_cookie                      │
│  - Forwards all headers to backend                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│               Hana Gateway (ECS/Fargate)                         │
│  - Validates request from trusted proxy (ALB IP range)          │
│  - Extracts user from X-Forwarded-User header                   │
│  - Creates/resumes session for user                             │
└─────────────────────────────────────────────────────────────────┘
```

### Hana Gateway Configuration

Configure the gateway to accept trusted-proxy authentication:

```yaml
# openclaw.config.yaml
gateway:
  auth:
    mode: trusted-proxy
    trustedProxy:
      userHeader: x-forwarded-user
      requiredHeaders:
        - x-forwarded-proto
      allowUsers: [] # Empty = allow all authenticated users
  trustedProxies:
    - 10.0.0.0/16 # VPC CIDR containing ALB
```

### Website Integration (Custom WebSocket Header)

To pass the authenticated user identity, create a custom WebSocket connection:

```tsx
// hooks/useHanaWithAuth.ts
import { useSession } from "next-auth/react";
import { useEffect, useRef } from "react";

export function useHanaWithAuth(gatewayUrl: string) {
  const { data: session } = useSession();
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    if (!session?.user?.email) return;

    // Note: Browser WebSocket API doesn't support custom headers directly.
    // For trusted-proxy auth, the ALB/proxy must inject the header.
    // Alternatively, pass user info in the connection URL or first message.

    const ws = new WebSocket(gatewayUrl);

    ws.onopen = () => {
      // Send authentication message with user identity
      ws.send(
        JSON.stringify({
          type: "auth",
          payload: { userId: session.user.email },
        }),
      );
    };

    wsRef.current = ws;

    return () => {
      ws.close();
    };
  }, [session, gatewayUrl]);

  return wsRef;
}
```

### Alternative: API Route Proxy

For full control over headers, proxy WebSocket through a Next.js API route:

```ts
// pages/api/hana-ws.ts (for pages router)
// or app/api/hana-ws/route.ts (for app router)

import { getServerSession } from "next-auth";

export async function GET(req: Request) {
  const session = await getServerSession();

  if (!session?.user?.email) {
    return new Response("Unauthorized", { status: 401 });
  }

  // Upgrade to WebSocket and proxy to Hana
  // This allows setting X-Forwarded-User header server-side
}
```

## WebSocket Protocol

### Message Types

#### chat.send - Send a message

```json
{
  "type": "chat.send",
  "payload": {
    "message": "Hello, Hana!",
    "sessionKey": "user-session-123"
  }
}
```

#### chat.history - Request conversation history

```json
{
  "type": "chat.history",
  "payload": {
    "sessionKey": "user-session-123",
    "limit": 50
  }
}
```

#### chat.response - Streaming response from Hana

```json
{
  "type": "chat.response",
  "payload": {
    "id": "msg-456",
    "content": "Hello! How can I help you today?",
    "done": true
  }
}
```

## Development

### Build the widget

```bash
cd apps/webchat
pnpm install
pnpm build
```

### Watch mode

```bash
pnpm dev
```

### Type checking

```bash
pnpm typecheck
```

## Troubleshooting

### Widget doesn't connect

1. Check the `gatewayUrl` is correct and accessible
2. Verify CORS is configured on the gateway
3. Check browser console for WebSocket errors

### Authentication failures

1. Ensure `trustedProxies` includes the ALB/proxy IP range
2. Verify `X-Forwarded-User` header is being set correctly
3. Check gateway logs for auth rejection reasons

### Session not persisting

1. Ensure sticky sessions are enabled on the ALB target group
2. Use a consistent `sessionKey` across page reloads
3. Store `sessionKey` in localStorage for persistence:

```tsx
const sessionKey = localStorage.getItem('hana-session') || generateNewKey();
localStorage.setItem('hana-session', sessionKey);

<HanaWidget sessionKey={sessionKey} ... />
```

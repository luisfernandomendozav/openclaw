/** Configuration for connecting to the Hana gateway */
export type HanaWidgetConfig = {
  /** WebSocket URL of the Hana gateway (e.g., "wss://hana.example.com/ws/") */
  gatewayUrl: string;
  /** Session key for conversation continuity */
  sessionKey?: string;
  /** User identifier (for trusted-proxy auth, passed via ALB headers) */
  userId?: string;
  /** Initial greeting message to display */
  greeting?: string;
  /** Widget title displayed in the header */
  title?: string;
  /** Placeholder text for the input field */
  placeholder?: string;
  /** Position of the widget button */
  position?: "bottom-right" | "bottom-left";
  /** Theme configuration */
  theme?: HanaWidgetTheme;
  /** Callback when connection state changes */
  onConnectionChange?: (connected: boolean) => void;
  /** Callback when an error occurs */
  onError?: (error: Error) => void;
};

export type HanaWidgetTheme = {
  /** Primary color for buttons and accents */
  primaryColor?: string;
  /** Background color of the chat window */
  backgroundColor?: string;
  /** Text color */
  textColor?: string;
  /** Border radius for the widget */
  borderRadius?: string;
};

/** Message in the chat */
export type ChatMessage = {
  id: string;
  role: "user" | "assistant" | "system";
  content: string;
  timestamp: Date;
  pending?: boolean;
};

/** WebSocket protocol message types */
export type WsMessage =
  | { type: "chat.send"; payload: { message: string; sessionKey?: string } }
  | { type: "chat.history"; payload: { sessionKey: string; limit?: number } }
  | { type: "chat.response"; payload: { id: string; content: string; done: boolean } }
  | { type: "chat.history.response"; payload: { messages: ChatMessage[] } }
  | { type: "error"; payload: { message: string; code?: string } };

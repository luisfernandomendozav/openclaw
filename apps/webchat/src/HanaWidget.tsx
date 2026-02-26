import { useCallback, useEffect, useRef, useState } from "react";
import type { ChatMessage, HanaWidgetConfig, HanaWidgetTheme } from "./types";
import { useHanaConnection } from "./useHanaConnection";

const DEFAULT_THEME: Required<HanaWidgetTheme> = {
  primaryColor: "#6366f1",
  backgroundColor: "#ffffff",
  textColor: "#1f2937",
  borderRadius: "12px",
};

export function HanaWidget(props: HanaWidgetConfig) {
  const {
    title = "Hana Assistant",
    greeting = "Hi! I'm Hana, your AI assistant. How can I help you today?",
    placeholder = "Type a message...",
    position = "bottom-right",
    theme: userTheme,
  } = props;

  const theme = { ...DEFAULT_THEME, ...userTheme };
  const [isOpen, setIsOpen] = useState(false);
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const {
    connectionState,
    messages,
    connect,
    disconnect,
    sendMessage,
  } = useHanaConnection(props);

  // Connect when widget opens
  useEffect(() => {
    if (isOpen && connectionState === "disconnected") {
      connect();
    }
  }, [isOpen, connectionState, connect]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      disconnect();
    };
  }, [disconnect]);

  // Auto-scroll to bottom
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      const trimmed = input.trim();
      if (!trimmed || connectionState !== "connected") {return;}

      sendMessage(trimmed);
      setInput("");
    },
    [input, connectionState, sendMessage]
  );

  const toggleWidget = useCallback(() => {
    setIsOpen((prev) => !prev);
  }, []);

  // Add greeting as first message if no messages
  const displayMessages: ChatMessage[] =
    messages.length === 0
      ? [
          {
            id: "greeting",
            role: "assistant",
            content: greeting,
            timestamp: new Date(),
          },
        ]
      : messages;

  const positionStyles =
    position === "bottom-right"
      ? { right: "20px", bottom: "20px" }
      : { left: "20px", bottom: "20px" };

  return (
    <div
      style={{
        position: "fixed",
        zIndex: 9999,
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        ...positionStyles,
      }}
    >
      {/* Chat Window */}
      {isOpen && (
        <div
          style={{
            position: "absolute",
            bottom: "70px",
            [position === "bottom-right" ? "right" : "left"]: 0,
            width: "380px",
            maxWidth: "calc(100vw - 40px)",
            height: "500px",
            maxHeight: "calc(100vh - 100px)",
            backgroundColor: theme.backgroundColor,
            borderRadius: theme.borderRadius,
            boxShadow: "0 10px 40px rgba(0,0,0,0.15)",
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
          }}
        >
          {/* Header */}
          <div
            style={{
              padding: "16px",
              backgroundColor: theme.primaryColor,
              color: "#ffffff",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <HanaLogo size={32} />
              <span style={{ fontWeight: 600, fontSize: "16px" }}>{title}</span>
            </div>
            <ConnectionIndicator state={connectionState} />
          </div>

          {/* Messages */}
          <div
            style={{
              flex: 1,
              overflowY: "auto",
              padding: "16px",
              display: "flex",
              flexDirection: "column",
              gap: "12px",
            }}
          >
            {displayMessages.map((msg) => (
              <MessageBubble
                key={msg.id}
                message={msg}
                theme={theme}
              />
            ))}
            <div ref={messagesEndRef} />
          </div>

          {/* Input */}
          <form
            onSubmit={handleSubmit}
            style={{
              padding: "12px 16px",
              borderTop: "1px solid #e5e7eb",
              display: "flex",
              gap: "8px",
            }}
          >
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder={placeholder}
              disabled={connectionState !== "connected"}
              style={{
                flex: 1,
                padding: "10px 14px",
                border: "1px solid #e5e7eb",
                borderRadius: "8px",
                fontSize: "14px",
                outline: "none",
                color: theme.textColor,
              }}
            />
            <button
              type="submit"
              disabled={connectionState !== "connected" || !input.trim()}
              style={{
                padding: "10px 16px",
                backgroundColor:
                  connectionState === "connected" && input.trim()
                    ? theme.primaryColor
                    : "#9ca3af",
                color: "#ffffff",
                border: "none",
                borderRadius: "8px",
                cursor:
                  connectionState === "connected" && input.trim()
                    ? "pointer"
                    : "not-allowed",
                fontWeight: 500,
              }}
            >
              Send
            </button>
          </form>
        </div>
      )}

      {/* Floating Button */}
      <button
        onClick={toggleWidget}
        aria-label={isOpen ? "Close chat" : "Open chat"}
        style={{
          width: "56px",
          height: "56px",
          borderRadius: "50%",
          backgroundColor: theme.primaryColor,
          border: "none",
          cursor: "pointer",
          boxShadow: "0 4px 12px rgba(0,0,0,0.15)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          transition: "transform 0.2s",
        }}
      >
        {isOpen ? (
          <CloseIcon color="#ffffff" />
        ) : (
          <HanaLogo size={28} color="#ffffff" />
        )}
      </button>
    </div>
  );
}

function MessageBubble({
  message,
  theme,
}: {
  message: ChatMessage;
  theme: Required<HanaWidgetTheme>;
}) {
  const isUser = message.role === "user";

  return (
    <div
      style={{
        alignSelf: isUser ? "flex-end" : "flex-start",
        maxWidth: "85%",
      }}
    >
      <div
        style={{
          padding: "10px 14px",
          borderRadius: "12px",
          backgroundColor: isUser ? theme.primaryColor : "#f3f4f6",
          color: isUser ? "#ffffff" : theme.textColor,
          fontSize: "14px",
          lineHeight: 1.5,
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
        }}
      >
        {message.content}
        {message.pending && (
          <span
            style={{
              display: "inline-block",
              marginLeft: "4px",
              animation: "hana-blink 1s infinite",
            }}
          >
            ...
          </span>
        )}
      </div>
    </div>
  );
}

function ConnectionIndicator({
  state,
}: {
  state: "connecting" | "connected" | "disconnected" | "error";
}) {
  const colors = {
    connecting: "#fbbf24",
    connected: "#10b981",
    disconnected: "#6b7280",
    error: "#ef4444",
  };

  const labels = {
    connecting: "Connecting...",
    connected: "Connected",
    disconnected: "Offline",
    error: "Error",
  };

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
      <div
        style={{
          width: "8px",
          height: "8px",
          borderRadius: "50%",
          backgroundColor: colors[state],
        }}
      />
      <span style={{ fontSize: "12px", opacity: 0.9 }}>{labels[state]}</span>
    </div>
  );
}

function HanaLogo({ size = 24, color = "currentColor" }: { size?: number; color?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <circle cx="12" cy="12" r="10" stroke={color} strokeWidth="2" />
      <path
        d="M8 14s1.5 2 4 2 4-2 4-2"
        stroke={color}
        strokeWidth="2"
        strokeLinecap="round"
      />
      <circle cx="9" cy="10" r="1.5" fill={color} />
      <circle cx="15" cy="10" r="1.5" fill={color} />
    </svg>
  );
}

function CloseIcon({ color = "currentColor" }: { color?: string }) {
  return (
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M18 6L6 18M6 6l12 12"
        stroke={color}
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

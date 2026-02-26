import { useCallback, useEffect, useRef, useState } from "react";
import type { ChatMessage, HanaWidgetConfig, WsMessage } from "./types";

type ConnectionState = "connecting" | "connected" | "disconnected" | "error";

export function useHanaConnection(config: HanaWidgetConfig) {
  const [connectionState, setConnectionState] = useState<ConnectionState>("disconnected");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pendingResponse, setPendingResponse] = useState<string | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sessionKeyRef = useRef<string>(config.sessionKey ?? generateSessionKey());

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    setConnectionState("connecting");

    const ws = new WebSocket(config.gatewayUrl);
    wsRef.current = ws;

    ws.addEventListener("open", () => {
      setConnectionState("connected");
      config.onConnectionChange?.(true);

      // Request chat history if we have a session
      if (sessionKeyRef.current) {
        const historyMsg: WsMessage = {
          type: "chat.history",
          payload: { sessionKey: sessionKeyRef.current, limit: 50 },
        };
        ws.send(JSON.stringify(historyMsg));
      }
    });

    ws.addEventListener("message", (event) => {
      try {
        const msg = JSON.parse(event.data as string) as WsMessage;
        handleMessage(msg);
      } catch {
        console.error("[HanaWidget] Failed to parse message:", event.data);
      }
    });

    ws.addEventListener("error", (error) => {
      console.error("[HanaWidget] WebSocket error:", error);
      setConnectionState("error");
      config.onError?.(new Error("WebSocket connection error"));
    });

    ws.addEventListener("close", () => {
      setConnectionState("disconnected");
      config.onConnectionChange?.(false);
      wsRef.current = null;

      // Attempt to reconnect after 3 seconds
      reconnectTimeoutRef.current = setTimeout(() => {
        connect();
      }, 3000);
    });
  }, [config]);

  const handleMessage = useCallback((msg: WsMessage) => {
    switch (msg.type) {
      case "chat.response": {
        const { id, content, done } = msg.payload;
        if (done) {
          setMessages((prev) => {
            // Find and update the pending message
            const existing = prev.find((m) => m.id === id);
            if (existing) {
              return prev.map((m) =>
                m.id === id ? { ...m, content, pending: false } : m
              );
            }
            // Add as new message if not found
            return [
              ...prev,
              {
                id,
                role: "assistant",
                content,
                timestamp: new Date(),
                pending: false,
              },
            ];
          });
          setPendingResponse(null);
        } else {
          // Streaming update
          setPendingResponse(content);
          setMessages((prev) => {
            const existing = prev.find((m) => m.id === id);
            if (existing) {
              return prev.map((m) =>
                m.id === id ? { ...m, content, pending: true } : m
              );
            }
            return [
              ...prev,
              {
                id,
                role: "assistant",
                content,
                timestamp: new Date(),
                pending: true,
              },
            ];
          });
        }
        break;
      }

      case "chat.history.response": {
        setMessages(msg.payload.messages);
        break;
      }

      case "error": {
        console.error("[HanaWidget] Server error:", msg.payload.message);
        break;
      }
    }
  }, []);

  const sendMessage = useCallback(
    (message: string) => {
      if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
        console.error("[HanaWidget] Cannot send: not connected");
        return;
      }

      // Add user message to local state immediately
      const userMessage: ChatMessage = {
        id: `user-${Date.now()}`,
        role: "user",
        content: message,
        timestamp: new Date(),
      };
      setMessages((prev) => [...prev, userMessage]);

      // Send to server
      const wsMsg: WsMessage = {
        type: "chat.send",
        payload: {
          message,
          sessionKey: sessionKeyRef.current,
        },
      };
      wsRef.current.send(JSON.stringify(wsMsg));
    },
    []
  );

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    setConnectionState("disconnected");
  }, []);

  useEffect(() => {
    return () => {
      disconnect();
    };
  }, [disconnect]);

  return {
    connectionState,
    messages,
    pendingResponse,
    connect,
    disconnect,
    sendMessage,
    sessionKey: sessionKeyRef.current,
  };
}

function generateSessionKey(): string {
  return `webchat-${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

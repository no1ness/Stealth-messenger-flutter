import { Check, CheckCheck, Shield } from "lucide-react";
import { cn } from "@/lib/utils";

interface ChatBubbleProps {
  message: string;
  timestamp: string;
  isSent: boolean;
  isDelivered?: boolean;
  isRead?: boolean;
  isEncrypted?: boolean;
}

export default function ChatBubble({
  message,
  timestamp,
  isSent,
  isDelivered = false,
  isRead = false,
  isEncrypted = true,
}: ChatBubbleProps) {
  return (
    <div
      className={cn(
        "flex w-full",
        isSent ? "justify-end" : "justify-start"
      )}
      data-testid={`message-bubble-${isSent ? 'sent' : 'received'}`}
    >
      <div
        className={cn(
          "max-w-[75%] rounded-2xl px-4 py-3",
          isSent
            ? "bg-primary text-primary-foreground rounded-br-sm ml-auto"
            : "bg-card text-card-foreground rounded-bl-sm"
        )}
      >
        <p className="text-base break-words whitespace-pre-wrap">{message}</p>
        <div className="flex items-center justify-end gap-1.5 mt-1">
          {isEncrypted && (
            <Shield className="w-3 h-3 opacity-70" data-testid="icon-encrypted" />
          )}
          <span className="text-xs opacity-70" data-testid="text-timestamp">{timestamp}</span>
          {isSent && (
            <span data-testid="status-delivery">
              {isRead ? (
                <CheckCheck className="w-4 h-4 text-chart-2" />
              ) : isDelivered ? (
                <CheckCheck className="w-4 h-4 opacity-70" />
              ) : (
                <Check className="w-4 h-4 opacity-70" />
              )}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

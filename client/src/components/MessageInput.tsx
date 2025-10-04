import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Paperclip, Send, Mic } from "lucide-react";

interface MessageInputProps {
  onSendMessage: (message: string) => void;
  onAttachment?: () => void;
  onVoiceMessage?: () => void;
  disabled?: boolean;
}

export default function MessageInput({
  onSendMessage,
  onAttachment,
  onVoiceMessage,
  disabled = false,
}: MessageInputProps) {
  const [message, setMessage] = useState("");

  const handleSend = () => {
    if (message.trim() && !disabled) {
      onSendMessage(message);
      setMessage("");
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <div className="flex items-center gap-2 p-4 border-t border-border bg-background">
      <Button
        size="icon"
        variant="ghost"
        onClick={onAttachment}
        disabled={disabled}
        data-testid="button-attachment"
      >
        <Paperclip className="w-5 h-5" />
      </Button>
      
      <div className="flex-1 relative">
        <Input
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          onKeyPress={handleKeyPress}
          placeholder="Type a message..."
          disabled={disabled}
          className="w-full pr-12 rounded-full"
          data-testid="input-message"
        />
      </div>
      
      <Button
        size="icon"
        variant="ghost"
        onClick={onVoiceMessage}
        disabled={disabled}
        data-testid="button-voice"
      >
        <Mic className="w-5 h-5" />
      </Button>
      
      <Button
        size="icon"
        onClick={handleSend}
        disabled={disabled || !message.trim()}
        data-testid="button-send"
      >
        <Send className="w-5 h-5" />
      </Button>
    </div>
  );
}

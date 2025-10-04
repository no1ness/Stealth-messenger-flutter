import { Lock, MessageSquare } from "lucide-react";
import { Button } from "@/components/ui/button";

interface EmptyStateProps {
  type: "chats" | "contacts";
  onAction?: () => void;
}

export default function EmptyState({ type, onAction }: EmptyStateProps) {
  const config = {
    chats: {
      icon: MessageSquare,
      title: "No conversations yet",
      description: "Start a secure conversation by adding a contact",
      actionText: "Add Contact",
    },
    contacts: {
      icon: Lock,
      title: "No contacts yet",
      description: "Add your first contact to start chatting securely",
      actionText: "Add Contact",
    },
  };

  const { icon: Icon, title, description, actionText } = config[type];

  return (
    <div
      className="flex flex-col items-center justify-center h-full p-8 text-center"
      data-testid={`empty-${type}`}
    >
      <div className="w-24 h-24 rounded-full bg-primary/10 flex items-center justify-center mb-6">
        <Icon className="w-12 h-12 text-primary" />
      </div>
      
      <h3 className="text-xl font-semibold mb-2">{title}</h3>
      <p className="text-muted-foreground mb-6 max-w-sm">{description}</p>
      
      {onAction && (
        <Button onClick={onAction} data-testid="button-action">
          {actionText}
        </Button>
      )}
    </div>
  );
}

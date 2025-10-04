import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { cn } from "@/lib/utils";

interface ChatListItemProps {
  id: string;
  name: string;
  lastMessage: string;
  timestamp: string;
  unreadCount?: number;
  isActive?: boolean;
  onClick?: () => void;
}

export default function ChatListItem({
  id,
  name,
  lastMessage,
  timestamp,
  unreadCount = 0,
  isActive = false,
  onClick,
}: ChatListItemProps) {
  const initials = name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  return (
    <div
      className={cn(
        "flex items-center gap-3 p-4 cursor-pointer hover-elevate active-elevate-2 relative",
        isActive && "bg-sidebar-accent"
      )}
      onClick={onClick}
      data-testid={`chat-item-${id}`}
    >
      <Avatar className="w-12 h-12 flex-shrink-0">
        <AvatarFallback className="bg-primary/10 text-primary font-medium">
          {initials}
        </AvatarFallback>
      </Avatar>
      
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-2 mb-1">
          <h3 className="font-semibold text-sm truncate" data-testid="text-name">
            {name}
          </h3>
          <span className="text-xs text-muted-foreground flex-shrink-0" data-testid="text-time">
            {timestamp}
          </span>
        </div>
        <p className="text-sm text-muted-foreground truncate" data-testid="text-preview">
          {lastMessage}
        </p>
      </div>
      
      {unreadCount > 0 && (
        <div
          className="absolute top-2 right-2 w-5 h-5 rounded-full bg-primary flex items-center justify-center"
          data-testid="badge-unread"
        >
          <span className="text-xs font-medium text-primary-foreground">
            {unreadCount > 9 ? "9+" : unreadCount}
          </span>
        </div>
      )}
    </div>
  );
}

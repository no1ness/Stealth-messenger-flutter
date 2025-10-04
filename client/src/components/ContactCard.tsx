import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { MessageSquare, Phone } from "lucide-react";
import { Badge } from "@/components/ui/badge";

interface ContactCardProps {
  id: string;
  name: string;
  userId: string;
  isVerified?: boolean;
  onMessage?: () => void;
  onCall?: () => void;
}

export default function ContactCard({
  id,
  name,
  userId,
  isVerified = false,
  onMessage,
  onCall,
}: ContactCardProps) {
  const initials = name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  return (
    <div
      className="flex items-center gap-4 p-4 bg-card rounded-lg border border-card-border hover-elevate"
      data-testid={`contact-card-${id}`}
    >
      <Avatar className="w-12 h-12 flex-shrink-0">
        <AvatarFallback className="bg-primary/10 text-primary font-medium">
          {initials}
        </AvatarFallback>
      </Avatar>
      
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <h3 className="font-semibold text-base truncate" data-testid="text-name">
            {name}
          </h3>
          {isVerified && (
            <Badge variant="secondary" className="text-xs" data-testid="badge-verified">
              Verified
            </Badge>
          )}
        </div>
        <p className="text-sm text-muted-foreground font-mono truncate" data-testid="text-userid">
          ID: {userId}
        </p>
      </div>
      
      <div className="flex gap-2 flex-shrink-0">
        <Button
          size="icon"
          variant="ghost"
          onClick={onMessage}
          data-testid="button-message"
        >
          <MessageSquare className="w-5 h-5" />
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onClick={onCall}
          data-testid="button-call"
        >
          <Phone className="w-5 h-5" />
        </Button>
      </div>
    </div>
  );
}

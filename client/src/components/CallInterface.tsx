import { useState } from "react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Mic, MicOff, PhoneOff, Volume2, VolumeX } from "lucide-react";
import { cn } from "@/lib/utils";

interface CallInterfaceProps {
  contactName: string;
  duration: string;
  onEndCall: () => void;
}

export default function CallInterface({
  contactName,
  duration,
  onEndCall,
}: CallInterfaceProps) {
  const [isMuted, setIsMuted] = useState(false);
  const [isSpeakerOn, setIsSpeakerOn] = useState(true);

  const initials = contactName
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  return (
    <div
      className="fixed inset-0 bg-background z-50 flex flex-col items-center justify-between p-8"
      data-testid="interface-call"
    >
      <div className="flex-1 flex flex-col items-center justify-center">
        <Avatar className="w-32 h-32 mb-6">
          <AvatarFallback className="bg-primary/10 text-primary font-semibold text-4xl">
            {initials}
          </AvatarFallback>
        </Avatar>
        
        <h2 className="text-2xl font-semibold mb-2" data-testid="text-name">
          {contactName}
        </h2>
        <p className="text-muted-foreground text-lg" data-testid="text-duration">
          {duration}
        </p>
      </div>
      
      <div className="flex items-center gap-6">
        <Button
          size="icon"
          variant={isSpeakerOn ? "secondary" : "outline"}
          className={cn("w-16 h-16 rounded-full", isSpeakerOn && "toggle-elevate toggle-elevated")}
          onClick={() => setIsSpeakerOn(!isSpeakerOn)}
          data-testid="button-speaker"
        >
          {isSpeakerOn ? (
            <Volume2 className="w-6 h-6" />
          ) : (
            <VolumeX className="w-6 h-6" />
          )}
        </Button>
        
        <Button
          size="icon"
          variant="destructive"
          className="w-20 h-20 rounded-full"
          onClick={onEndCall}
          data-testid="button-endcall"
        >
          <PhoneOff className="w-8 h-8" />
        </Button>
        
        <Button
          size="icon"
          variant={isMuted ? "secondary" : "outline"}
          className={cn("w-16 h-16 rounded-full", isMuted && "toggle-elevate toggle-elevated")}
          onClick={() => setIsMuted(!isMuted)}
          data-testid="button-mute"
        >
          {isMuted ? (
            <MicOff className="w-6 h-6" />
          ) : (
            <Mic className="w-6 h-6" />
          )}
        </Button>
      </div>
    </div>
  );
}

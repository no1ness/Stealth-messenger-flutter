import { Shield, ShieldCheck, ShieldAlert } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

interface EncryptionBadgeProps {
  status: "encrypted" | "verified" | "warning";
  className?: string;
}

export default function EncryptionBadge({ status, className }: EncryptionBadgeProps) {
  const config = {
    encrypted: {
      icon: Shield,
      text: "E2E Encrypted",
      variant: "secondary" as const,
    },
    verified: {
      icon: ShieldCheck,
      text: "Verified",
      variant: "secondary" as const,
    },
    warning: {
      icon: ShieldAlert,
      text: "Unverified",
      variant: "outline" as const,
    },
  };

  const { icon: Icon, text, variant } = config[status];

  return (
    <Badge
      variant={variant}
      className={cn("gap-1", className)}
      data-testid={`badge-${status}`}
    >
      <Icon className="w-3 h-3" />
      <span className="text-xs">{text}</span>
    </Badge>
  );
}

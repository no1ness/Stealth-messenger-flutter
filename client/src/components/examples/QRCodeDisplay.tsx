import QRCodeDisplay from '../QRCodeDisplay';
import { Toaster } from "@/components/ui/toaster";

export default function QRCodeDisplayExample() {
  return (
    <div className="p-6 bg-background max-w-md mx-auto">
      <QRCodeDisplay
        data="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        title="Your User ID"
        description="Share this QR code with contacts to connect securely"
      />
      <Toaster />
    </div>
  );
}

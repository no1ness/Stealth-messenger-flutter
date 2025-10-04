import { useEffect, useRef } from "react";
import QRCode from "qrcode";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Copy, Download } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

interface QRCodeDisplayProps {
  data: string;
  title?: string;
  description?: string;
}

export default function QRCodeDisplay({
  data,
  title = "Your QR Code",
  description = "Share this code to add contacts",
}: QRCodeDisplayProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const { toast } = useToast();

  useEffect(() => {
    if (canvasRef.current && data) {
      QRCode.toCanvas(canvasRef.current, data, {
        width: 256,
        margin: 2,
        color: {
          dark: "#3b82f6",
          light: "#ffffff",
        },
      });
    }
  }, [data]);

  const handleCopy = () => {
    navigator.clipboard.writeText(data);
    toast({
      title: "Copied!",
      description: "User ID copied to clipboard",
    });
  };

  const handleDownload = () => {
    if (canvasRef.current) {
      const url = canvasRef.current.toDataURL("image/png");
      const link = document.createElement("a");
      link.download = "qr-code.png";
      link.href = url;
      link.click();
      toast({
        title: "Downloaded!",
        description: "QR code saved as image",
      });
    }
  };

  return (
    <Card data-testid="card-qrcode">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col items-center gap-4">
        <div className="bg-white p-4 rounded-lg">
          <canvas ref={canvasRef} />
        </div>
        
        <div className="flex flex-col gap-2 w-full">
          <div className="flex items-center gap-2">
            <code className="flex-1 px-3 py-2 bg-muted rounded text-sm font-mono truncate" data-testid="text-userid">
              {data}
            </code>
            <Button
              size="icon"
              variant="ghost"
              onClick={handleCopy}
              data-testid="button-copy"
            >
              <Copy className="w-4 h-4" />
            </Button>
          </div>
          
          <Button
            variant="outline"
            onClick={handleDownload}
            className="w-full"
            data-testid="button-download"
          >
            <Download className="w-4 h-4 mr-2" />
            Download QR Code
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

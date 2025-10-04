import { useState, useEffect } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import QRCodeDisplay from "@/components/QRCodeDisplay";
import { Download, Upload, Save } from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import { generateUserId, generateKeyPair, exportPrivateKey } from "@/lib/crypto";

export default function Profile() {
  const [userId, setUserId] = useState("");
  const [nickname, setNickname] = useState("");
  const { toast } = useToast();

  useEffect(() => {
    const storedUserId = localStorage.getItem("userId");
    const storedNickname = localStorage.getItem("nickname");
    
    if (!storedUserId) {
      const newUserId = generateUserId();
      localStorage.setItem("userId", newUserId);
      setUserId(newUserId);
      
      generateKeyPair().then(keyPair => {
        exportPrivateKey(keyPair.privateKey).then(privateKeyStr => {
          localStorage.setItem("privateKey", privateKeyStr);
        });
      });
    } else {
      setUserId(storedUserId);
    }
    
    if (storedNickname) {
      setNickname(storedNickname);
    }
  }, []);

  const handleSaveNickname = () => {
    localStorage.setItem("nickname", nickname);
    toast({
      title: "Saved!",
      description: "Your nickname has been updated",
    });
  };

  const handleExportKey = () => {
    const privateKey = localStorage.getItem("privateKey");
    if (privateKey) {
      const blob = new Blob([privateKey], { type: "text/plain" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.download = "secure-chat-key.txt";
      link.href = url;
      link.click();
      URL.revokeObjectURL(url);
      
      toast({
        title: "Key Exported",
        description: "Keep this file safe! You'll need it to restore your account.",
      });
    }
  };

  const handleImportKey = () => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".txt";
    input.onchange = (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (file) {
        const reader = new FileReader();
        reader.onload = (event) => {
          const privateKey = event.target?.result as string;
          localStorage.setItem("privateKey", privateKey);
          toast({
            title: "Key Imported",
            description: "Your private key has been restored",
          });
        };
        reader.readAsText(file);
      }
    };
    input.click();
  };

  return (
    <div className="flex flex-col h-screen overflow-y-auto bg-background">
      <div className="p-6 space-y-6 max-w-2xl mx-auto w-full">
        <div>
          <h1 className="text-3xl font-bold mb-2">Profile</h1>
          <p className="text-muted-foreground">
            Manage your account and security settings
          </p>
        </div>
        
        <Card>
          <CardHeader>
            <CardTitle>Personal Information</CardTitle>
            <CardDescription>
              Your nickname is only stored locally
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="nickname">Nickname</Label>
              <div className="flex gap-2">
                <Input
                  id="nickname"
                  placeholder="Enter your nickname"
                  value={nickname}
                  onChange={(e) => setNickname(e.target.value)}
                  data-testid="input-nickname"
                />
                <Button onClick={handleSaveNickname} data-testid="button-save">
                  <Save className="w-4 h-4 mr-2" />
                  Save
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
        
        <QRCodeDisplay
          data={userId}
          title="Your User ID"
          description="Share this QR code or ID with contacts to connect"
        />
        
        <Card>
          <CardHeader>
            <CardTitle>Security Keys</CardTitle>
            <CardDescription>
              Export your private key for backup or import to restore
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Button
              variant="outline"
              className="w-full"
              onClick={handleExportKey}
              data-testid="button-export"
            >
              <Download className="w-4 h-4 mr-2" />
              Export Private Key
            </Button>
            <Button
              variant="outline"
              className="w-full"
              onClick={handleImportKey}
              data-testid="button-import"
            >
              <Upload className="w-4 h-4 mr-2" />
              Import Private Key
            </Button>
            <p className="text-xs text-muted-foreground">
              ⚠️ Never share your private key with anyone. Keep it safe!
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

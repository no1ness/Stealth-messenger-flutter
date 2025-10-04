import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { UserPlus, QrCode } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

interface AddContactDialogProps {
  onAddContact: (userId: string, nickname: string) => void;
}

export default function AddContactDialog({ onAddContact }: AddContactDialogProps) {
  const [userId, setUserId] = useState("");
  const [nickname, setNickname] = useState("");
  const [open, setOpen] = useState(false);
  const { toast } = useToast();

  const handleAddByID = () => {
    if (userId.trim()) {
      onAddContact(userId, nickname || "Unknown Contact");
      setUserId("");
      setNickname("");
      setOpen(false);
      toast({
        title: "Contact Added",
        description: `${nickname || "Contact"} has been added to your list`,
      });
    }
  };

  const handleScanQR = () => {
    toast({
      title: "QR Scanner",
      description: "QR code scanning will be available soon",
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button data-testid="button-addcontact">
          <UserPlus className="w-4 h-4 mr-2" />
          Add Contact
        </Button>
      </DialogTrigger>
      <DialogContent data-testid="dialog-addcontact">
        <DialogHeader>
          <DialogTitle>Add New Contact</DialogTitle>
          <DialogDescription>
            Add a contact by entering their User ID or scanning their QR code
          </DialogDescription>
        </DialogHeader>
        
        <Tabs defaultValue="id" className="w-full">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="id" data-testid="tab-userid">User ID</TabsTrigger>
            <TabsTrigger value="qr" data-testid="tab-qrcode">QR Code</TabsTrigger>
          </TabsList>
          
          <TabsContent value="id" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="userId">User ID</Label>
              <Input
                id="userId"
                placeholder="a1b2c3d4-e5f6-7890..."
                value={userId}
                onChange={(e) => setUserId(e.target.value)}
                data-testid="input-userid"
              />
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="nickname">Nickname (optional)</Label>
              <Input
                id="nickname"
                placeholder="Enter a nickname"
                value={nickname}
                onChange={(e) => setNickname(e.target.value)}
                data-testid="input-nickname"
              />
            </div>
            
            <Button
              className="w-full"
              onClick={handleAddByID}
              disabled={!userId.trim()}
              data-testid="button-submit"
            >
              Add Contact
            </Button>
          </TabsContent>
          
          <TabsContent value="qr" className="space-y-4">
            <div className="flex flex-col items-center justify-center py-8 gap-4">
              <QrCode className="w-24 h-24 text-muted-foreground" />
              <p className="text-sm text-muted-foreground text-center">
                QR code scanning will be available in the full version
              </p>
              <Button onClick={handleScanQR} data-testid="button-scan">
                Open Scanner
              </Button>
            </div>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}

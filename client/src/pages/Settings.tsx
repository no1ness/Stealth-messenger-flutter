import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Shield, Bell, Moon, Trash2 } from "lucide-react";

export default function Settings() {
  return (
    <div className="flex flex-col h-screen overflow-y-auto bg-background">
      <div className="p-6 space-y-6 max-w-2xl mx-auto w-full">
        <div>
          <h1 className="text-3xl font-bold mb-2">Settings</h1>
          <p className="text-muted-foreground">
            Configure your privacy and notification preferences
          </p>
        </div>
        
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <Shield className="w-5 h-5 text-primary" />
              <CardTitle>Privacy & Security</CardTitle>
            </div>
            <CardDescription>
              Control how your data is stored and shared
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>End-to-End Encryption</Label>
                <p className="text-sm text-muted-foreground">
                  Always enabled for all messages
                </p>
              </div>
              <Switch checked disabled data-testid="switch-encryption" />
            </div>
            
            <Separator />
            
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>Auto-delete messages</Label>
                <p className="text-sm text-muted-foreground">
                  Automatically delete old messages
                </p>
              </div>
              <Switch data-testid="switch-autodelete" />
            </div>
            
            <Separator />
            
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>Contact verification</Label>
                <p className="text-sm text-muted-foreground">
                  Verify new contacts before chatting
                </p>
              </div>
              <Switch defaultChecked data-testid="switch-verification" />
            </div>
          </CardContent>
        </Card>
        
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <Bell className="w-5 h-5 text-primary" />
              <CardTitle>Notifications</CardTitle>
            </div>
            <CardDescription>
              Manage how you receive notifications
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>New message notifications</Label>
                <p className="text-sm text-muted-foreground">
                  Get notified of new messages
                </p>
              </div>
              <Switch defaultChecked data-testid="switch-notifications" />
            </div>
            
            <Separator />
            
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>Call notifications</Label>
                <p className="text-sm text-muted-foreground">
                  Get notified of incoming calls
                </p>
              </div>
              <Switch defaultChecked data-testid="switch-callnotif" />
            </div>
          </CardContent>
        </Card>
        
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <Moon className="w-5 h-5 text-primary" />
              <CardTitle>Appearance</CardTitle>
            </div>
            <CardDescription>
              Customize the look and feel
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label>Dark mode</Label>
                <p className="text-sm text-muted-foreground">
                  Use dark theme (always on for security)
                </p>
              </div>
              <Switch checked disabled data-testid="switch-darkmode" />
            </div>
          </CardContent>
        </Card>
        
        <Card className="border-destructive/50">
          <CardHeader>
            <div className="flex items-center gap-2">
              <Trash2 className="w-5 h-5 text-destructive" />
              <CardTitle className="text-destructive">Danger Zone</CardTitle>
            </div>
            <CardDescription>
              Irreversible actions
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Button
              variant="destructive"
              className="w-full"
              data-testid="button-cleardata"
            >
              Clear All Local Data
            </Button>
            <p className="text-xs text-muted-foreground">
              This will delete all messages, contacts, and keys from this device
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

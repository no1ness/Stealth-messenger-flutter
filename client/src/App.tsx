import { Switch, Route, useLocation } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { MessageSquare, Users, User, Settings as SettingsIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import Chats from "@/pages/Chats";
import Contacts from "@/pages/Contacts";
import Profile from "@/pages/Profile";
import Settings from "@/pages/Settings";

function BottomNav() {
  const [location, setLocation] = useLocation();

  const navItems = [
    { path: "/", icon: MessageSquare, label: "Chats" },
    { path: "/contacts", icon: Users, label: "Contacts" },
    { path: "/profile", icon: User, label: "Profile" },
    { path: "/settings", icon: SettingsIcon, label: "Settings" },
  ];

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-sidebar border-t border-sidebar-border md:hidden z-40">
      <div className="flex items-center justify-around h-16">
        {navItems.map((item) => {
          const isActive = location === item.path;
          return (
            <button
              key={item.path}
              onClick={() => setLocation(item.path)}
              className={cn(
                "flex flex-col items-center justify-center gap-1 flex-1 h-full hover-elevate active-elevate-2",
                isActive && "text-primary"
              )}
              data-testid={`nav-${item.label.toLowerCase()}`}
            >
              <item.icon className="w-5 h-5" />
              <span className="text-xs font-medium">{item.label}</span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}

function Router() {
  return (
    <Switch>
      <Route path="/" component={Chats} />
      <Route path="/contacts" component={Contacts} />
      <Route path="/profile" component={Profile} />
      <Route path="/settings" component={Settings} />
      <Route>
        <div className="flex items-center justify-center h-screen">
          <p className="text-muted-foreground">Page not found</p>
        </div>
      </Route>
    </Switch>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <div className="pb-16 md:pb-0">
          <Router />
        </div>
        <BottomNav />
        <Toaster />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;

import { useState, useEffect } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import ChatListItem from "@/components/ChatListItem";
import ChatBubble from "@/components/ChatBubble";
import MessageInput from "@/components/MessageInput";
import EncryptionBadge from "@/components/EncryptionBadge";
import EmptyState from "@/components/EmptyState";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Phone } from "lucide-react";

const INITIAL_MESSAGES = [
  { id: "1", message: "Hi! How are you?", timestamp: "10:30", isSent: false },
  { id: "2", message: "I'm good, thanks! The encryption is working great.", timestamp: "10:31", isSent: true, isDelivered: true, isRead: true },
  { id: "3", message: "Yes, all our messages are secure 🔒", timestamp: "10:32", isSent: false },
];

export default function Chats() {
  const [selectedChat, setSelectedChat] = useState<string | null>(() => {
    return localStorage.getItem("selectedChat") || null;
  });
  const [searchQuery, setSearchQuery] = useState("");
  const [messages, setMessages] = useState(() => {
    const chatId = localStorage.getItem("selectedChat") || "1";
    const stored = localStorage.getItem(`messages_${chatId}`);
    return stored ? JSON.parse(stored) : INITIAL_MESSAGES;
  });

  const chats = [
    { id: "1", name: "Alice Johnson", lastMessage: "Yes, all our messages are secure", timestamp: "10:32", unreadCount: 0 },
    { id: "2", name: "Bob Smith", lastMessage: "Voice call ended", timestamp: "Yesterday", unreadCount: 2 },
    { id: "3", name: "Carol Williams", lastMessage: "See you tomorrow!", timestamp: "2 days ago", unreadCount: 0 },
  ];

  useEffect(() => {
    if (selectedChat) {
      localStorage.setItem("selectedChat", selectedChat);
      const stored = localStorage.getItem(`messages_${selectedChat}`);
      if (stored) {
        setMessages(JSON.parse(stored));
      } else {
        setMessages(INITIAL_MESSAGES);
      }
    }
  }, [selectedChat]);

  useEffect(() => {
    if (selectedChat) {
      localStorage.setItem(`messages_${selectedChat}`, JSON.stringify(messages));
    }
  }, [messages, selectedChat]);

  const filteredChats = chats.filter(chat =>
    chat.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleSendMessage = (message: string) => {
    const newMessages = [
      ...messages,
      {
        id: Date.now().toString(),
        message,
        timestamp: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
        isSent: true,
        isDelivered: false,
        isRead: false,
      },
    ];
    setMessages(newMessages);
  };

  const currentChat = chats.find(c => c.id === selectedChat);

  return (
    <div className="flex h-screen">
      <div className="w-full md:w-80 flex flex-col border-r border-border bg-sidebar">
        <div className="p-4 border-b border-sidebar-border">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Search chats..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
              data-testid="input-search"
            />
          </div>
        </div>
        
        <div className="flex-1 overflow-y-auto">
          {filteredChats.length > 0 ? (
            filteredChats.map((chat) => (
              <ChatListItem
                key={chat.id}
                {...chat}
                isActive={selectedChat === chat.id}
                onClick={() => setSelectedChat(chat.id)}
              />
            ))
          ) : (
            <EmptyState type="chats" />
          )}
        </div>
      </div>
      
      <div className="flex-1 flex flex-col">
        {selectedChat && currentChat ? (
          <>
            <div className="flex items-center justify-between p-4 border-b border-border bg-background">
              <div className="flex items-center gap-3">
                <Avatar className="w-10 h-10">
                  <AvatarFallback className="bg-primary/10 text-primary font-medium">
                    {currentChat.name.split(" ").map(n => n[0]).join("").toUpperCase().slice(0, 2)}
                  </AvatarFallback>
                </Avatar>
                <div>
                  <h2 className="font-semibold" data-testid="text-chatname">{currentChat.name}</h2>
                  <EncryptionBadge status="encrypted" className="mt-0.5" />
                </div>
              </div>
              <Button size="icon" variant="ghost" data-testid="button-call">
                <Phone className="w-5 h-5" />
              </Button>
            </div>
            
            <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-background">
              {messages.map((msg) => (
                <ChatBubble
                  key={msg.id}
                  message={msg.message}
                  timestamp={msg.timestamp}
                  isSent={msg.isSent}
                  isDelivered={msg.isDelivered}
                  isRead={msg.isRead}
                  isEncrypted={true}
                />
              ))}
            </div>
            
            <MessageInput
              onSendMessage={handleSendMessage}
              onAttachment={() => console.log('Attachment clicked')}
              onVoiceMessage={() => console.log('Voice message clicked')}
            />
          </>
        ) : (
          <EmptyState type="chats" />
        )}
      </div>
    </div>
  );
}

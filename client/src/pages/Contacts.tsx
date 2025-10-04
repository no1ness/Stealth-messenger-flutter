import { useState } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import ContactCard from "@/components/ContactCard";
import AddContactDialog from "@/components/AddContactDialog";
import EmptyState from "@/components/EmptyState";

export default function Contacts() {
  const [searchQuery, setSearchQuery] = useState("");
  const [contacts, setContacts] = useState([
    { id: "1", name: "Alice Johnson", userId: "a1b2c3d4-e5f6-7890", isVerified: true },
    { id: "2", name: "Bob Smith", userId: "x9y8z7w6-v5u4-3210", isVerified: false },
    { id: "3", name: "Carol Williams", userId: "m5n6o7p8-q9r0-1234", isVerified: true },
  ]);

  const filteredContacts = contacts.filter(contact =>
    contact.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    contact.userId.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleAddContact = (userId: string, nickname: string) => {
    setContacts([
      ...contacts,
      {
        id: Date.now().toString(),
        name: nickname,
        userId,
        isVerified: false,
      },
    ]);
  };

  return (
    <div className="flex flex-col h-screen bg-background">
      <div className="p-4 border-b border-border">
        <div className="flex items-center gap-3">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Search contacts..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
              data-testid="input-search"
            />
          </div>
          <AddContactDialog onAddContact={handleAddContact} />
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto p-4">
        {filteredContacts.length > 0 ? (
          <div className="space-y-3 max-w-2xl mx-auto">
            {filteredContacts.map((contact) => (
              <ContactCard
                key={contact.id}
                {...contact}
                onMessage={() => console.log('Message:', contact.name)}
                onCall={() => console.log('Call:', contact.name)}
              />
            ))}
          </div>
        ) : (
          <EmptyState
            type="contacts"
            onAction={() => console.log('Add contact')}
          />
        )}
      </div>
    </div>
  );
}

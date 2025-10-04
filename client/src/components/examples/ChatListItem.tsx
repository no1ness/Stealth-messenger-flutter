import ChatListItem from '../ChatListItem';

export default function ChatListItemExample() {
  return (
    <div className="bg-sidebar max-w-sm">
      <ChatListItem
        id="1"
        name="Alice Johnson"
        lastMessage="The encryption keys have been exchanged"
        timestamp="10:30"
        unreadCount={3}
        isActive={false}
        onClick={() => console.log('Chat clicked')}
      />
      <ChatListItem
        id="2"
        name="Bob Smith"
        lastMessage="Voice call ended"
        timestamp="Yesterday"
        unreadCount={0}
        isActive={true}
        onClick={() => console.log('Chat clicked')}
      />
      <ChatListItem
        id="3"
        name="Carol Williams"
        lastMessage="Sent an encrypted image"
        timestamp="2 days ago"
        unreadCount={1}
        isActive={false}
        onClick={() => console.log('Chat clicked')}
      />
    </div>
  );
}

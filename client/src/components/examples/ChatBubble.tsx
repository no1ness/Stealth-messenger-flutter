import ChatBubble from '../ChatBubble';

export default function ChatBubbleExample() {
  return (
    <div className="flex flex-col gap-3 p-6 bg-background max-w-2xl">
      <ChatBubble
        message="Hi! This is an encrypted message"
        timestamp="10:30"
        isSent={false}
        isEncrypted={true}
      />
      <ChatBubble
        message="Great! The encryption is working perfectly 🔒"
        timestamp="10:31"
        isSent={true}
        isDelivered={true}
        isRead={false}
        isEncrypted={true}
      />
      <ChatBubble
        message="All messages are end-to-end encrypted and secure"
        timestamp="10:32"
        isSent={true}
        isDelivered={true}
        isRead={true}
        isEncrypted={true}
      />
    </div>
  );
}

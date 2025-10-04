import MessageInput from '../MessageInput';

export default function MessageInputExample() {
  return (
    <div className="bg-background max-w-2xl">
      <MessageInput
        onSendMessage={(msg) => console.log('Sending message:', msg)}
        onAttachment={() => console.log('Attachment clicked')}
        onVoiceMessage={() => console.log('Voice message clicked')}
      />
    </div>
  );
}

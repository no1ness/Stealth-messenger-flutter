import CallInterface from '../CallInterface';

export default function CallInterfaceExample() {
  return (
    <CallInterface
      contactName="Alice Johnson"
      duration="02:34"
      onEndCall={() => console.log('Call ended')}
    />
  );
}

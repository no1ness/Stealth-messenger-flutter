import ContactCard from '../ContactCard';

export default function ContactCardExample() {
  return (
    <div className="flex flex-col gap-3 p-6 bg-background max-w-md">
      <ContactCard
        id="1"
        name="Alice Johnson"
        userId="a1b2c3d4-e5f6-7890"
        isVerified={true}
        onMessage={() => console.log('Message clicked')}
        onCall={() => console.log('Call clicked')}
      />
      <ContactCard
        id="2"
        name="Bob Smith"
        userId="x9y8z7w6-v5u4-3210"
        isVerified={false}
        onMessage={() => console.log('Message clicked')}
        onCall={() => console.log('Call clicked')}
      />
    </div>
  );
}

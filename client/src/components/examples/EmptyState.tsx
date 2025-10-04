import EmptyState from '../EmptyState';

export default function EmptyStateExample() {
  return (
    <div className="grid grid-cols-2 gap-4 h-screen">
      <div className="bg-background border-r border-border">
        <EmptyState
          type="chats"
          onAction={() => console.log('Add contact clicked')}
        />
      </div>
      <div className="bg-background">
        <EmptyState
          type="contacts"
          onAction={() => console.log('Add contact clicked')}
        />
      </div>
    </div>
  );
}

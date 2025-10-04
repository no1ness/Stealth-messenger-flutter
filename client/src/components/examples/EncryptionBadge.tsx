import EncryptionBadge from '../EncryptionBadge';

export default function EncryptionBadgeExample() {
  return (
    <div className="flex flex-wrap gap-3 p-6 bg-background">
      <EncryptionBadge status="encrypted" />
      <EncryptionBadge status="verified" />
      <EncryptionBadge status="warning" />
    </div>
  );
}

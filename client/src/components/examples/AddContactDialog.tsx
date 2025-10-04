import AddContactDialog from '../AddContactDialog';
import { Toaster } from "@/components/ui/toaster";

export default function AddContactDialogExample() {
  return (
    <div className="p-6 bg-background">
      <AddContactDialog
        onAddContact={(userId, nickname) => 
          console.log('Adding contact:', userId, nickname)
        }
      />
      <Toaster />
    </div>
  );
}

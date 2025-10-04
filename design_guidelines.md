# Design Guidelines: Secure Cross-Platform Messenger

## Design Approach
**System-Based with Signal/Telegram Inspiration**
- Primary Reference: Signal's security-focused minimalism with Telegram's modern polish
- Core Principle: Trust through simplicity - every element reinforces security and clarity
- Visual Language: Clean, purposeful, with subtle depth to indicate encryption states

## Color Palette

### Dark Mode (Primary)
- **Background Base**: 217 19% 12% (deep charcoal)
- **Surface Elevated**: 217 19% 18% (chat backgrounds)
- **Surface Overlay**: 217 19% 24% (modals, dropdowns)
- **Primary Brand**: 210 100% 56% (security blue - for encrypted indicators, CTAs)
- **Primary Hover**: 210 100% 48%
- **Text Primary**: 0 0% 98%
- **Text Secondary**: 0 0% 70%
- **Text Tertiary**: 0 0% 50%
- **Success**: 142 71% 45% (encrypted, delivered)
- **Warning**: 38 92% 50% (pending encryption)
- **Error**: 0 84% 60% (failed delivery)
- **Divider**: 217 19% 28%

### Light Mode (Secondary)
- **Background Base**: 0 0% 100%
- **Surface Elevated**: 0 0% 97%
- **Surface Overlay**: 0 0% 100%
- **Primary Brand**: 210 100% 48%
- **Text Primary**: 0 0% 12%
- **Text Secondary**: 0 0% 40%
- **Text Tertiary**: 0 0% 60%

## Typography
- **Primary Font**: 'Inter' (Google Fonts) - clean, modern, excellent readability
- **Monospace Font**: 'JetBrains Mono' (for user IDs, keys)
- **Scale**: 
  - Headers: font-semibold text-2xl (24px)
  - Body: font-normal text-base (16px)
  - Small/Meta: font-normal text-sm (14px)
  - Tiny/Timestamps: font-normal text-xs (12px)
  - User IDs: font-mono text-sm

## Layout System
**Spacing Units**: Consistent use of Tailwind's 4, 6, 8, 12, 16 units
- Component padding: p-4 (16px) standard, p-6 (24px) generous
- Section gaps: gap-4 for tight grouping, gap-6 for sections
- Container max-width: max-w-7xl for main layout
- Chat bubbles: mx-4 my-2 spacing
- List items: p-4 with gap-3 between elements

## Component Library

### Navigation & Layout
- **Top Bar**: Fixed header with h-16, subtle border-b, app logo/title left, profile/settings right
- **Bottom Navigation** (Mobile): Fixed bottom with 4 tabs - Chats, Contacts, Calls, Settings
- **Sidebar** (Desktop): w-80 fixed left panel with chat list, search at top
- **Chat Container**: Flex-1 with messages area and input footer

### Chat Elements
- **Message Bubbles**: 
  - Sent: bg-primary rounded-2xl rounded-br-sm max-w-[75%] ml-auto
  - Received: bg-surface-elevated rounded-2xl rounded-bl-sm max-w-[75%]
  - Padding: px-4 py-3
  - Include: timestamp text-xs, encryption indicator icon (shield), delivery status
- **Chat List Items**: 
  - h-20 with avatar (w-12 h-12 rounded-full), name, last message preview, timestamp
  - Unread indicator: absolute top-2 right-2 w-2 h-2 rounded-full bg-primary
  - Active state: bg-surface-elevated

### Input & Forms
- **Message Input**: 
  - Fixed bottom bar with rounded-full text input
  - Attachment button (paperclip), voice button, send button (paper plane icon)
  - bg-surface-elevated with border focus:ring-2 ring-primary
- **Search**: Sticky top with icon-left, rounded-lg, h-12
- **Settings Sections**: Grouped with dividers, toggle switches for options

### Security Indicators
- **Encryption Badge**: Small shield icon with text "E2E Encrypted" - subtle but always visible in chat header
- **Verification Indicators**: 
  - Green checkmark for verified contacts
  - Yellow warning for unverified
  - QR code scanner button prominent in contact add flow

### Modals & Overlays
- **Contact Add Modal**: Centered, max-w-md, with tabs for ID/QR code input
- **Profile/Settings**: Slide-in from right on mobile, overlay on desktop
- **Call Interface**: Full-screen overlay with large avatar, mute/end call buttons (rounded-full, large touch targets)

### Media & Files
- **Images in Chat**: Rounded-lg, max-w-xs, with lightbox on click
- **Voice Messages**: Waveform visualization, play button, duration
- **File Attachments**: Card-style with icon, filename, size, download button

### Empty States
- **No Chats**: Centered illustration (lock + speech bubble), text "Start a secure conversation", prominent "Add Contact" CTA
- **No Contacts**: QR code icon, "Add your first contact" message

## Animations
**Minimal & Purposeful**
- Message send: Subtle scale-in (scale-95 to scale-100) over 150ms
- Chat entry: Slide-in from right (translate-x-full to translate-x-0) 200ms
- Typing indicator: Pulse animation on dots
- Connection status: Fade transition for online/offline states
- NO scroll-triggered animations
- NO decorative transitions

## Icons
**Font Awesome (via CDN)** - consistent 20px for UI, 16px for inline elements
- Shield (encryption)
- Lock (security)
- QR Code (contact add)
- Phone/Video (calls)
- Paperclip (attachments)
- Paper Plane (send)
- Check/Double Check (delivery status)

## Accessibility & Dark Mode
- All components maintain WCAG AA contrast in both modes
- Form inputs: Consistent styling with visible focus rings
- Touch targets: Minimum 44x44px for mobile
- Keyboard navigation: Full support with visible focus indicators
- Screen reader labels for all interactive elements

## Images
No hero images - this is a utility app. Only use:
- User avatars (generated or uploaded, rounded-full)
- Shared media thumbnails in chats
- QR codes for contact exchange
- Empty state illustrations (simple, outlined style)

## Key Differentiators
- **Trust Through Design**: Every visual element reinforces security (shields, locks, encryption badges)
- **Information Density**: Efficient use of space - no wasted pixels in chat lists or message views
- **Instant Clarity**: Message states (sending, delivered, read, encrypted) immediately visible
- **Functional Beauty**: Polish comes from precision, not decoration
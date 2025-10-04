# SecureChat - Private Messenger

## Overview

SecureChat is a privacy-focused, cross-platform messenger application designed for small communities (up to several thousand users). The application prioritizes maximum privacy, end-to-end encryption, and minimal server-side data storage. It features a modern, clean interface inspired by Signal's security-focused minimalism and Telegram's polish.

The application is built as a full-stack web application with plans for mobile deployment, emphasizing client-side encryption, minimal data footprint, and secure peer-to-peer communication capabilities.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture

**Technology Stack:**
- React with TypeScript for type safety
- Vite as the build tool and development server
- Wouter for lightweight client-side routing
- TanStack React Query for server state management
- Tailwind CSS for styling with custom design system

**UI Component Library:**
- Radix UI primitives for accessible, unstyled components
- shadcn/ui component system with "new-york" style variant
- Custom design tokens based on dark mode primary (Signal/Telegram inspired)

**Design Philosophy:**
- Dark mode first with light mode support
- System-based design with security indicators
- Color palette emphasizing trust through security blue (#3b82f6)
- Typography: Inter for UI, JetBrains Mono for technical data (IDs, keys)
- Consistent spacing using Tailwind's 4px-based scale

**Client-Side Security:**
- Web Crypto API for cryptographic operations
- RSA-OAEP (2048-bit) for key generation and encryption
- Local key storage (private keys never leave the device)
- Client-side encryption/decryption of all messages

**Key Features:**
- No traditional authentication (no phone/email/password)
- UUID-based user identification
- QR code generation for contact sharing
- Local contact list storage
- Client-side message encryption before transmission

### Backend Architecture

**Runtime & Framework:**
- Node.js with Express.js server
- TypeScript for type safety across the stack
- ES Modules for modern JavaScript

**Development Setup:**
- Hot module replacement via Vite in development
- Middleware-based request logging
- Error handling with status code propagation

**Session Management:**
- Designed for session-based authentication
- Uses connect-pg-simple for PostgreSQL session store (configured but minimal server state)

**API Structure:**
- RESTful API design (routes prefixed with `/api`)
- JSON request/response format
- Credential-based requests for session management

### Data Storage Solutions

**Database:**
- PostgreSQL via Neon Database serverless driver
- Drizzle ORM for type-safe database operations
- Migration support via drizzle-kit

**Schema Design (Minimal Server Storage):**

1. **Users Table:**
   - UUID primary key (generated server-side)
   - Public key (for encryption)
   - Optional nickname
   - Created timestamp
   - *Note: No passwords, emails, or phone numbers stored*

2. **Chats Table:**
   - UUID primary key
   - Array of member UUIDs
   - Created timestamp

3. **Messages Table:**
   - UUID primary key
   - Chat ID reference
   - Sender ID reference
   - Ciphertext (encrypted content only)
   - Message type
   - Created timestamp
   - *Note: Server never sees plaintext messages*

**Client-Side Storage:**
- LocalStorage for:
  - User ID
  - Private encryption keys
  - Nickname
  - Contact list
- Encrypted backups for key recovery

**Rationale:** The database stores the absolute minimum required for message delivery and synchronization. All sensitive data (private keys, plaintext messages, contact lists) remain client-side. The server acts primarily as a relay and synchronization point.

### Authentication and Authorization

**Authentication Model:**
- Passwordless system based on cryptographic key pairs
- First-run experience generates UUID and RSA key pair
- Public key registration with server
- Private key stored locally with export/import capability
- Optional nickname (not required for identity)

**Authorization:**
- Session-based (prepared for implementation)
- User identified by UUID
- Access control based on chat membership (member UUID arrays)

**Security Features:**
- End-to-end encryption (always enabled, non-optional)
- Verification badges for trusted contacts
- QR code based contact exchange
- Key export for account recovery

### External Dependencies

**Third-Party Services:**
- Neon Database (PostgreSQL hosting) - serverless database solution
- Planned: VPS hosting outside specific jurisdictions for server deployment
- Planned: WebRTC infrastructure for P2P voice calls

**NPM Packages:**
- **UI/Styling:**
  - @radix-ui/* family (accessible component primitives)
  - tailwindcss with autoprefixer
  - class-variance-authority (CVA) for component variants
  - clsx + tailwind-merge for className utilities
  
- **Forms & Validation:**
  - react-hook-form with @hookform/resolvers
  - zod for schema validation
  - drizzle-zod for database schema validation

- **Cryptography:**
  - Web Crypto API (built-in browser API)
  - qrcode library for QR code generation

- **Database:**
  - drizzle-orm for type-safe queries
  - @neondatabase/serverless for PostgreSQL connection
  - connect-pg-simple for session storage

- **Development:**
  - tsx for TypeScript execution
  - esbuild for server bundling
  - vite with @vitejs/plugin-react
  - Replit-specific plugins for development environment

**Alternatives Considered:**
- Supabase was mentioned in requirements but Neon + Drizzle chosen for more control
- Signal Protocol libraries considered but Web Crypto API chosen for simplicity in initial implementation
- Native mobile apps (Flutter) planned but web-first approach for rapid development

**Integration Points:**
- Database: Connection string via environment variable (DATABASE_URL)
- Session store: PostgreSQL-backed sessions
- Future: WebRTC for peer-to-peer voice/video calls
- Future: Push notification services for mobile apps

**Deployment Considerations:**
- Designed for VPS deployment outside restrictive jurisdictions
- Environment-based configuration
- Production build separates client (Vite) and server (esbuild)
- Static file serving in production mode
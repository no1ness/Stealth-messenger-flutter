import type { StealthMessage } from '../types';

import { type EncryptedPayload, EncryptedSession } from './encryption';

const RTC_CONFIG: RTCConfiguration = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
  ],
};

const DATA_CHANNEL_LABEL = 'stealth-messaging';

interface P2PFrame {
  encrypted: true;
  payload: EncryptedPayload;
}

interface ChatConnection {
  pc: RTCPeerConnection;
  dataChannel: RTCDataChannel | null;
  session: EncryptedSession;
  onMessage?: (msg: StealthMessage) => void;
  onStateChange?: (state: string) => void;
}

export class PeerConnectionManager {
  private connections = new Map<string, ChatConnection>();

  private localUserId: string;

  constructor(localUserId: string) {
    this.localUserId = localUserId;
  }

  async createConnection(
    chatId: string,
    sharedSecret: ArrayBuffer,
    onMessage: (msg: StealthMessage) => void,
    onStateChange?: (state: string) => void,
  ): Promise<RTCPeerConnection> {
    this.closeConnection(chatId);

    const session = new EncryptedSession();
    await session.initWithSecret(sharedSecret);

    const pc = new RTCPeerConnection(RTC_CONFIG);
    const dataChannel = pc.createDataChannel(DATA_CHANNEL_LABEL, {
      ordered: true,
    });

    const entry: ChatConnection = { pc, dataChannel, session, onMessage, onStateChange };
    this.connections.set(chatId, entry);

    this.setupDataChannel(dataChannel, chatId, entry);

    pc.oniceconnectionstatechange = () => {
      const state = pc.iceConnectionState;
      onStateChange?.(state);
      if (state === 'failed' || state === 'disconnected') {
        this.closeConnection(chatId);
      }
    };

    pc.ondatachannel = (event) => {
      this.setupDataChannel(event.channel, chatId, entry);
      entry.dataChannel = event.channel;
    };

    return pc;
  }

  getConnection(chatId: string): RTCPeerConnection | undefined {
    return this.connections.get(chatId)?.pc;
  }

  getSession(chatId: string): EncryptedSession | undefined {
    return this.connections.get(chatId)?.session;
  }

  closeConnection(chatId: string): void {
    const entry = this.connections.get(chatId);
    if (entry) {
      entry.dataChannel?.close();
      entry.pc.close();
      this.connections.delete(chatId);
    }
  }

  closeAll(): void {
    for (const chatId of this.connections.keys()) {
      this.closeConnection(chatId);
    }
  }

  async sendMessage(chatId: string, msg: StealthMessage): Promise<boolean> {
    const entry = this.connections.get(chatId);
    const channel = entry?.dataChannel;
    if (!channel || channel.readyState !== 'open' || !entry.session.isReady()) return false;

    try {
      const payload = await entry.session.encrypt(JSON.stringify(msg));
      const frame: P2PFrame = { encrypted: true, payload };
      channel.send(JSON.stringify(frame));
      return true;
    } catch {
      return false;
    }
  }

  private setupDataChannel(
    channel: RTCDataChannel,
    chatId: string,
    entry: ChatConnection,
  ): void {
    channel.onopen = () => {
    };

    channel.onclose = () => {
    };

    channel.onmessage = async (event) => {
      try {
        const frame = JSON.parse(event.data) as P2PFrame;
        if (!frame.encrypted || !entry.session.isReady()) return;
        const decrypted = await entry.session.decrypt(frame.payload);
        const msg = JSON.parse(decrypted) as StealthMessage;
        entry.onMessage?.(msg);
      } catch {
        // parse or decrypt error
      }
    };

    channel.onerror = () => {
    };
  }
}

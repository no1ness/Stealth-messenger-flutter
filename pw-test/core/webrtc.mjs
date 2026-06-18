export function createPeerConnection(iceServers = []) {
  return new RTCPeerConnection({ iceServers });
}

export function createDataChannel(pc, label) {
  return pc.createDataChannel(label);
}

export function waitForIceConnected(pc, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("ICE timeout")), timeoutMs);
    pc.oniceconnectionstatechange = () => {
      if (pc.iceConnectionState === "connected") {
        clearTimeout(timer);
        resolve();
      }
    };
  });
}

export function waitForDataChannelOpen(dc, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("DC timeout")), timeoutMs);
    dc.onopen = () => {
      clearTimeout(timer);
      resolve();
    };
  });
}

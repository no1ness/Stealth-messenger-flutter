export function pbTimestampToUnix(pbTimestamp?: string): number | undefined {
  if (!pbTimestamp) return undefined;
  const date = new Date(pbTimestamp);
  return isNaN(date.getTime()) ? undefined : Math.floor(date.getTime() / 1000);
}

export function unixToPbTimestamp(unix: number): string {
  return new Date(unix * 1000).toISOString();
}

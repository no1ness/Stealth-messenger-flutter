import type { ApiFormattedText } from '../../types';

export function buildApiFormattedText(text: string): ApiFormattedText {
  return { text, entities: undefined };
}

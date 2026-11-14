import { SHOULD_RENDER_TEST_IDS } from '../config';

export default function getTestId(id: string) {
  return SHOULD_RENDER_TEST_IDS ? id : undefined;
}

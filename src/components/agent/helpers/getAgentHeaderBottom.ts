/**
 * The lowest edge of the Agent's headers, with what is attached under them, over a span of the window. What flies over
 * the Agent's screens passes under this edge, since the headers stay over the feed, the chats and their pictures.
 */
export default function getAgentHeaderBottom(left: number, right: number) {
  let bottom = 0;
  document.querySelectorAll<HTMLElement>('[data-agent-header], [data-agent-header-accessory]').forEach((header) => {
    const rect = header.getBoundingClientRect();
    if (rect.width && rect.right > left && rect.left < right) bottom = Math.max(bottom, rect.bottom);
  });

  return bottom || undefined;
}

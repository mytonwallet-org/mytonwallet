import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentHeader from './AgentHeader';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('AgentHeader', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
  });

  function findSupportButton() {
    return root.querySelector<HTMLButtonElement>('button[aria-label="$agent_support_contact"]');
  }

  async function getMenuItemTexts() {
    root.querySelector<HTMLButtonElement>('button[aria-label="Open Menu"]')!.click();
    await pause(50);
    return [...portals.querySelectorAll('button')].map(({ textContent }) => textContent);
  }

  it('shows its title content in the title\'s place', async () => {
    TeactDOM.render(<AgentHeader title="News" titleContent={<div data-title-content>Switch</div>} />, root);
    await pause(20);

    expect(root.querySelector('[data-title-content]')).not.toBeNull();
    expect(root.querySelector('[role="heading"]')).toBeNull();
  });

  it('calls support from its button, which the chat menu does not repeat', async () => {
    const onRequestSupport = jest.fn();
    TeactDOM.render(
      <AgentHeader isMenuVisible canRequestSupport onRequestSupport={onRequestSupport} onDelete={jest.fn()} />,
      root,
    );
    await pause(20);

    const button = findSupportButton()!;
    expect(button.disabled).toBe(false);
    // It stands before the "…" button
    expect(button.nextElementSibling!.getAttribute('aria-label')).toBe('Open Menu');
    button.click();
    expect(onRequestSupport).toHaveBeenLastCalledWith('header');

    expect(await getMenuItemTexts()).toEqual(['Delete Chat']);
    expect(onRequestSupport).toHaveBeenCalledTimes(1);
  });

  it('shows the support button without the "…" button while the menu has nothing to offer', async () => {
    TeactDOM.render(<AgentHeader isMenuVisible canRequestSupport onRequestSupport={jest.fn()} />, root);
    await pause(20);

    expect(findSupportButton()!.disabled).toBe(false);
    expect(root.querySelector('button[aria-label="Open Menu"]')).toBeNull();
  });

  it('disables support while the chat cannot call it', async () => {
    const onRequestSupport = jest.fn();
    TeactDOM.render(<AgentHeader isMenuVisible onRequestSupport={onRequestSupport} onDelete={jest.fn()} />, root);
    await pause(20);

    expect(findSupportButton()!.disabled).toBe(true);
  });

  it('has no support without `onRequestSupport`', async () => {
    TeactDOM.render(<AgentHeader isMenuVisible canRequestSupport onDelete={jest.fn()} />, root);
    await pause(20);

    expect(findSupportButton()).toBeNull();
    expect(await getMenuItemTexts()).toEqual(['Delete Chat']);
  });

  it('leads with the wallet\'s Back button, chevron and label, which goes back', async () => {
    const onBack = jest.fn();
    TeactDOM.render(<AgentHeader isScrolled={false} title="Staking" onBack={onBack} />, root);
    await pause(20);

    const button = root.querySelector('button')!;
    expect(button.textContent).toBe('Back');
    expect(button.querySelector('i')!.classList).toContain('icon-chevron-left');
    button.click();
    expect(onBack).toHaveBeenCalledTimes(1);
  });

  it('has no Back button on the chat list', async () => {
    TeactDOM.render(<AgentHeader isScrolled={false} />, root);
    await pause(20);

    expect(root.querySelector('button')).toBeNull();
  });
});

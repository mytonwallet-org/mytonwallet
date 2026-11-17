export async function moveAnchor({ github, context, core, key }) {
  // The gate reads this tag rather than reconstructing the same fact from run history:
  // the commit it points at is what shipped, and the tagger date is when it shipped.
  const tag = `cadence-anchor-${key}`;
  // Every commit master still holds answers this, and a rerun of a run whose commit the
  // branch has since dropped does not, which is what separates the two refusals below.
  const stillOnMaster = async (sha) => {
    const tip = await github.rest.repos.getBranch({ ...context.repo, branch: 'master' });
    const diff = await github.rest.repos.compareCommits({
      ...context.repo,
      base: sha,
      head: tip.data.commit.sha,
    });
    return diff.data.status === 'ahead' || diff.data.status === 'identical';
  };
  // A rerun of an older run arrives with that run's own commit, and moving the anchor back
  // would put already-built commits outside the next window and buy a second build.
  try {
    const ref = await github.rest.git.getRef({ ...context.repo, ref: `tags/${tag}` });
    const current = await github.rest.git.getTag({ ...context.repo, tag_sha: ref.data.object.sha });
    const diff = await github.rest.repos.compareCommits({
      ...context.repo,
      base: current.data.object.sha,
      head: context.sha,
    });
    // A rewritten master leaves the anchor on a line of its own, where no later push can
    // ever be ahead of it, so refusing on that alone would retire the window for good.
    if (diff.data.status === 'diverged' && await stillOnMaster(context.sha)) {
      core.warning(`anchor ${current.data.object.sha.slice(0, 10)} is not on master any more, adopting this run`);
    } else if (diff.data.status !== 'ahead') {
      core.warning(`anchor already at ${current.data.object.sha.slice(0, 10)}, which is not behind this run`);
      return 'kept';
    }
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  const object = await github.rest.git.createTag({
    ...context.repo,
    tag,
    message: `iOS build uploaded from ${context.sha}`,
    object: context.sha,
    type: 'commit',
    tagger: {
      name: 'github-actions[bot]',
      email: '41898282+github-actions[bot]@users.noreply.github.com',
      date: new Date().toISOString(),
    },
  });
  try {
    await github.rest.git.updateRef({
      ...context.repo,
      ref: `tags/${tag}`,
      sha: object.data.sha,
      force: true,
    });
  } catch (error) {
    if (error.status !== 404 && error.status !== 422) throw error;
    await github.rest.git.createRef({
      ...context.repo,
      ref: `refs/tags/${tag}`,
      sha: object.data.sha,
    });
  }
  return 'moved';
}

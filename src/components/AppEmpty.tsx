import React from '../lib/teact/teact';

import styles from './AppEmpty.module.scss';

function AppEmpty() {
  return (
    <div className={styles.root}>
      <img src="/logo.svg" alt="" className={styles.img} />
    </div>
  );
}

export default AppEmpty;

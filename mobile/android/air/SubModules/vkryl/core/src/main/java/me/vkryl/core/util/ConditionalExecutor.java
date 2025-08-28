/*
 * This file is a part of X-Core
 * Copyright © Vyacheslav Krylov 2014
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * File created on 25/03/2019
 */

package me.vkryl.core.util;

import androidx.annotation.Nullable;

import java.util.concurrent.LinkedBlockingQueue;

import me.vkryl.core.lambda.FutureBool;
import me.vkryl.core.lambda.RunnableBool;

/**
 * Class that consumes {@link Runnable} and executes them when {@link ConditionalExecutor#condition} returns true
 */
public final class ConditionalExecutor {
  private final FutureBool condition;

  @Nullable
  private RunnableBool onTaskAdded, onTaskRemoved;

  public ConditionalExecutor (FutureBool condition) {
    this.condition = condition;
    checkCondition();
  }

  public ConditionalExecutor onAddRemove (RunnableBool onTaskAdded, RunnableBool onTaskRemoved) {
    this.onTaskAdded = onTaskAdded;
    this.onTaskRemoved = onTaskRemoved;
    return this;
  }

  private final LinkedBlockingQueue<Runnable> pendingTasks = new LinkedBlockingQueue<>();

  private final Object lock = new Object();
  private boolean currentState;

  private boolean checkCondition () {
    boolean newState = condition.getBoolValue();
    boolean stateChanged;
    synchronized (lock) {
      stateChanged = this.currentState != newState;
      this.currentState = newState;
    }
    if (stateChanged && newState) {
      executePendingTasks();
    }
    return newState;
  }

  private void onTaskAdded (boolean isAboutToExecute) {
    if (onTaskAdded != null) {
      onTaskAdded.runWithBool(isAboutToExecute);
    }
  }

  private void onTaskRemoved (boolean justFinishedExecution) {
    if (onTaskRemoved != null) {
      onTaskRemoved.runWithBool(justFinishedExecution);
    }
  }

  private void performTask (Runnable task) {
    onTaskAdded(true);
    RuntimeException error = null;
    try {
      task.run();
    } catch (RuntimeException e) {
      error = e;
    }
    onTaskRemoved(true);
    if (error != null) {
      throw error;
    }
  }

  private void executePendingTasks () {
    Runnable task;
    while ((task = pendingTasks.poll()) != null) {
      performTask(task);
      onTaskRemoved(false);
    }
  }

  public void executeOrPostponeTask (Runnable task) {
    boolean execute = checkCondition();
    boolean taskScheduled;
    if (!execute) {
      synchronized (lock) {
        // Making sure we don't add task to the pendingTasks when no longer needed
        taskScheduled = !this.currentState && pendingTasks.offer(task);
      }
    } else {
      taskScheduled = false;
    }
    if (!taskScheduled) {
      performTask(task);
    } else {
      onTaskAdded(false);
    }
  }

  public void notifyConditionChanged () {
    notifyConditionChanged(false);
  }

  /**
   * Notify whether {@link #condition} result might have changed
   *
   * @param forceExecutePendingTasks execute all pending tasks regardless of current condition
   */
  public void notifyConditionChanged (boolean forceExecutePendingTasks) {
    if (!checkCondition() && forceExecutePendingTasks) {
      executePendingTasks();
    }
  }
}

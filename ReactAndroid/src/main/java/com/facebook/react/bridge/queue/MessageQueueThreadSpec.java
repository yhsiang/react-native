/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

package com.facebook.react.bridge.queue;

/**
 * Spec for creating a MessageQueueThread.
 */
public class MessageQueueThreadSpec {

  private static final MessageQueueThreadSpec MAIN_UI_SPEC =
      new MessageQueueThreadSpec(ThreadType.MAIN_UI, "main_ui");

  // According to https://docs.oracle.com/javase/7/docs/api/java/lang/Thread.html#Thread(java.lang.ThreadGroup,%20java.lang.Runnable,%20java.lang.String,%20long),
  // using zero for stack size in Thread(...) is equivalent to not specifying it
  private static final long DEFAULT_STACK_SIZE = 0;

  protected static enum ThreadType {
    MAIN_UI,
    NEW_BACKGROUND,
  }

  public static MessageQueueThreadSpec newBackgroundThreadSpec(String name) {
    return new MessageQueueThreadSpec(ThreadType.NEW_BACKGROUND, name);
  }

  public static MessageQueueThreadSpec newBackgroundThreadSpec(String name, long stackSize) {
    return new MessageQueueThreadSpec(ThreadType.NEW_BACKGROUND, name, stackSize);
  }

  public static MessageQueueThreadSpec mainThreadSpec() {
    return MAIN_UI_SPEC;
  }

  private final ThreadType mThreadType;
  private final String mName;
  private final long mStackSize;

  private MessageQueueThreadSpec(ThreadType threadType, String name) {
    mThreadType = threadType;
    mName = name;
    mStackSize = DEFAULT_STACK_SIZE;
  }

  private MessageQueueThreadSpec(ThreadType threadType, String name, long stackSize) {
    mThreadType = threadType;
    mName = name;
    mStackSize = stackSize;
  }

  public ThreadType getThreadType() {
    return mThreadType;
  }

  public String getName() {
    return mName;
  }

  public long getStackSize() {
    return mStackSize;
  }
}

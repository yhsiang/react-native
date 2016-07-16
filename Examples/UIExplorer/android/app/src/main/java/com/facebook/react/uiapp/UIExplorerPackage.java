/**
 * The examples provided by Facebook are for non-commercial testing and
 * evaluation purposes only.
 *
 * Facebook reserves all rights not expressly granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NON INFRINGEMENT. IN NO EVENT SHALL
 * FACEBOOK BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
 * AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

package com.facebook.react.uiapp;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import com.facebook.react.ReactPackage;
import com.facebook.react.animated.NativeAnimatedModule;
import com.facebook.react.bridge.JavaScriptModule;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.uimanager.ViewManager;

class UIExplorerPackage implements ReactPackage {
  @Override
  public List<NativeModule> createNativeModules(ReactApplicationContext context) {
    return Arrays.<NativeModule>asList(
        new NativeAnimatedModule(context));
  }

  @Override
  public List<Class<? extends JavaScriptModule>> createJSModules() {
    return new ArrayList<>(0);
  }

  @Override
  public List<ViewManager> createViewManagers(ReactApplicationContext reactContext) {
    return new ArrayList<>(0);
  }
}

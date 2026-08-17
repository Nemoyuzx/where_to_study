import { AppModel } from '../model/AppModel';
import { RootView } from '../view/RootView';

// 应用根页面：唯一的 AppModel 在这里创建并通过 @Provider 注入整个组件树，
// 与 iOS 端 @StateObject AppModel + environmentObject 的注入方式对应。
@Entry
@Component
struct Index {
  @Provider('appModel') model: AppModel = new AppModel();

  build() {
    RootView()
  }
}

// ohosTest 测试聚合入口。
import primaryNavigationSmokeTest from './PrimaryNavigationSmoke.test';
import credentialStoreDeviceTest from './CredentialStoreDevice.test';

export default function testsuite() {
  primaryNavigationSmokeTest();
  credentialStoreDeviceTest();
}

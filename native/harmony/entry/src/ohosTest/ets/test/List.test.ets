// ohosTest 测试聚合入口。
import primaryNavigationSmokeTest from './PrimaryNavigationSmoke.test';
import credentialStoreDeviceTest from './CredentialStoreDevice.test';
import sjdNetworkDeviceTest from './SjdNetworkDevice.test';
import jsonFileDeviceTest from './JsonFileDevice.test';

export default function testsuite() {
  primaryNavigationSmokeTest();
  credentialStoreDeviceTest();
  sjdNetworkDeviceTest();
  jsonFileDeviceTest();
}

import { describe, it, expect } from '@ohos/hypium';
import { Credentials } from '../main/ets/store/CredentialStore';
import { AssignmentDeadlineItem } from '../main/ets/net/CalendarDailyInfoClient';
import { AssignmentCatalogPublicationSink, UCloudAssignmentClient } from '../main/ets/net/UCloudAssignmentClient';
import { NewAssignmentTracker } from '../main/ets/common/NewAssignmentTracker';

function assignment(id: string): AssignmentDeadlineItem {
  return new AssignmentDeadlineItem(id, 'Synthetic ' + id, 'Synthetic course', '2026-10-06 23:59:00', null, 'course');
}

export default function assignmentPublicationTest() {
  describe('AssignmentPublication', () => {
    it('calendar_first_network_then_cached_catalog_publishes_new_items_once', 0, async () => {
      const credentials: Credentials = new Credentials('synthetic', 'fixture', '', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      const tracker: NewAssignmentTracker = new NewAssignmentTracker();
      let requests: number = 0;
      let publications: number = 0;
      let alerts: string[] = [];
      const client: UCloudAssignmentClient = new UCloudAssignmentClient(async (_credentials: Credentials): Promise<AssignmentDeadlineItem[]> => {
        requests++;
        return [assignment('old'), assignment('new')];
      });
      client.observeCatalogPublications((_credentials: Credentials): AssignmentCatalogPublicationSink =>
        (items: AssignmentDeadlineItem[], complete: boolean, cached: boolean, current: () => boolean): void => {
          expect(current()).assertTrue();
          publications++;
          alerts = alerts.concat(tracker.accept(items.map((item: AssignmentDeadlineItem): string => item.id), complete, cached));
        });
      client.installValidatedCache(credentials, [], [assignment('old')], 1, 1);
      await Promise.all([client.fetch(credentials, '2026-10-06'), client.fetch(credentials, '2026-10-07')]);
      await client.fetchCatalog(credentials);
      expect(requests).assertEqual(1);
      expect(publications).assertEqual(2);
      expect(alerts.join(',')).assertEqual('new');
    });
    it('retired_network_owner_never_publishes_to_new_identity', 0, async () => {
      let release: (items: AssignmentDeadlineItem[]) => void = (_items: AssignmentDeadlineItem[]): void => {};
      const delayed: Promise<AssignmentDeadlineItem[]> = new Promise<AssignmentDeadlineItem[]>((resolve): void => { release = resolve; });
      const client: UCloudAssignmentClient = new UCloudAssignmentClient(async (_credentials: Credentials): Promise<AssignmentDeadlineItem[]> => delayed);
      let publications: number = 0;
      client.observeCatalogPublications((_credentials: Credentials): AssignmentCatalogPublicationSink =>
        (_items: AssignmentDeadlineItem[], _complete: boolean, _cached: boolean, _current: () => boolean): void => { publications++; });
      const work: Promise<AssignmentDeadlineItem[]> = client.fetch(new Credentials('old-account', 'fixture'), '2026-10-06');
      client.reset();
      release([assignment('late')]);
      await work;
      expect(publications).assertEqual(0);
    });
  });
}

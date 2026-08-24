import { DateParts } from './StrictDates';

export class CalendarViewportPreloadPlan {
  readonly selectedDate: DateParts;
  readonly markerDays: DateParts[];
  readonly holidayYears: number[];

  constructor(selectedDate: DateParts, markerDays: DateParts[], holidayYears: number[]) {
    this.selectedDate = selectedDate;
    this.markerDays = markerDays;
    this.holidayYears = holidayYears;
  }
}

export interface CalendarViewportPreloadTarget {
  prewarmCalendarViewport(selectedDate: DateParts, markerDays: DateParts[],
    holidayYears: number[]): void;
}

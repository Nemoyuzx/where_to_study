package com.nemoyu.wheretostudy.nativeapp

import android.app.Activity
import android.app.AlertDialog

internal fun showAcademicExamSchedule(activity: Activity, exams: ExamSchedule?) {
    val text = buildList {
        add(activity.uiText(AcademicScheduleLogic.statusText(exams)))
        exams?.items.orEmpty().forEach { exam ->
            val date = exam.date.ifBlank { activity.uiText("日期待定") }
            val time = if (AcademicScheduleLogic.minute(exam.startTime) != null && AcademicScheduleLogic.minute(exam.endTime) != null)
                "${exam.startTime}–${exam.endTime}" else activity.uiText("时间待定")
            add(listOf(exam.name, "$date · $time", exam.room, exam.timeText).filter(String::isNotBlank).joinToString("\n"))
        }
    }.joinToString("\n\n")
    AlertDialog.Builder(activity).setTitle(activity.uiText("考试安排"))
        .setMessage(text).setPositiveButton(activity.uiText("完成"), null).show()
}

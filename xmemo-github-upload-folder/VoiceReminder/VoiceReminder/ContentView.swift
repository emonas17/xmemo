import Darwin
import SwiftUI

private enum Phase: Equatable {
    case preparing
    case recording
    case chooseWhen
    /// Atidaryta iš pranešimo – automatinis grojimas pagal pranešimo ID.
    case playback(notificationId: String)
    case needsSettings
    case exitingAfterSchedule
}

private enum DayPreset: Int, CaseIterable {
    case tomorrow = 1
    case dayAfterTomorrow = 2
    case dayAfterThat = 3

    var title: String {
        switch self {
        case .tomorrow: return AppLanguage.text(lt: "Rytoj", en: "Tomorrow")
        case .dayAfterTomorrow: return AppLanguage.text(lt: "Poryt", en: "Day after")
        case .dayAfterThat: return AppLanguage.text(lt: "Užporyt", en: "In 3 days")
        }
    }
}

private enum DayPeriod: String, CaseIterable {
    case morning
    case afternoon
    case evening

    var title: String {
        switch self {
        case .morning: return AppLanguage.text(lt: "Ryte", en: "Morning")
        case .afternoon: return AppLanguage.text(lt: "Dieną", en: "Afternoon")
        case .evening: return AppLanguage.text(lt: "Vakare", en: "Evening")
        }
    }
}

private enum RepeatMode: String, CaseIterable, Identifiable {
    case once
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: return AppLanguage.text(lt: "Vieną kartą", en: "Once")
        case .custom: return AppLanguage.text(lt: "Kartoti dienomis", en: "Repeat days")
        }
    }
}

struct ContentView: View {
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var soundPreviewer = NotificationSoundPreviewer()
    @ObservedObject private var playbackRouter = NotificationPlaybackRouter.shared
    @State private var phase: Phase = .preparing
    @State private var status: String = ""
    @State private var isBusy = false
    @State private var recordingPulse = false
    @State private var showCustomDate = false
    @State private var showCustomRepeatTime = false
    @State private var showTimeSettings = false
    @State private var repeatMode: RepeatMode = .once
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var reminderTitle = ReminderTitleGenerator.fallbackTitle
    @State private var customRemindAt = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var customRepeatTime = Date()
    /// Įrašymo pabaigos laikas – jo valanda/minutės naudojamos „Rytoj / Poryt / Užporyt“.
    @State private var timeAnchor = Date()

    @AppStorage("morningHour") private var morningHour = 8
    @AppStorage("afternoonHour") private var afternoonHour = 13
    @AppStorage("eveningHour") private var eveningHour = 18
    @AppStorage("notificationSoundName") private var notificationSoundName = NotificationSoundOption.defaultValue.rawValue
    @AppStorage("playReminderOnSpeaker") private var playReminderOnSpeaker = true

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 16) {
            headerView

            ScrollView {
                VStack(spacing: 20) {
                    if phase == .recording {
                        recordingCircle
                    } else if phase == .preparing || phase == .exitingAfterSchedule {
                        VStack(spacing: 16) {
                            ProgressView()
                            if phase == .exitingAfterSchedule {
                                Text(AppLanguage.text(lt: "Suplanuota", en: "Scheduled"))
                                    .font(.headline)
                            }
                        }
                        .padding(.vertical, 40)
                    } else if phase == .chooseWhen {
                        chooseWhenSection
                    } else if case .playback(let nid) = phase {
                        ReminderPlaybackView(
                            notificationId: nid,
                            title: ReminderAudioStore.title(forNotificationId: nid),
                            showsStopRepeating: ReminderAudioStore.isRepeating(notificationId: nid),
                            playOnSpeaker: playReminderOnSpeaker
                        ) {
                            exit(0)
                        } onSnooze15: {
                            Task { await snoozePlayback(notificationId: nid, until: Date().addingTimeInterval(15 * 60)) }
                        } onSnooze60: {
                            Task { await snoozePlayback(notificationId: nid, until: Date().addingTimeInterval(60 * 60)) }
                        } onSnoozeTomorrow: {
                            let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(24 * 60 * 60)
                            Task { await snoozePlayback(notificationId: nid, until: date) }
                        } onStopRepeating: {
                            Task { await stopRepeating(notificationId: nid) }
                        }
                    } else {
                        needsSettingsSection
                    }

                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
            }
        }
        .safeAreaPadding(.top, 12)
        .padding(.horizontal, 20)
        .task {
            await runLaunchFlow()
        }
        .onChange(of: playbackRouter.pendingNotificationId) { _, notificationId in
            guard let notificationId else { return }
            openPlayback(notificationId: notificationId)
        }
        .onChange(of: recorder.isRecording) { _, recording in
            recordingPulse = recording
        }
        .onChange(of: repeatMode) { _, mode in
            if mode == .custom {
                showCustomDate = false
            } else {
                showCustomRepeatTime = false
            }
        }
        .task(id: phase) {
            guard phase == .recording else { return }
            while recorder.isRecording {
                await MainActor.run {
                    recorder.updateMeters()
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        .sheet(isPresented: $showTimeSettings) {
            ReminderTimeSettingsView(
                morningHour: $morningHour,
                afternoonHour: $afternoonHour,
                eveningHour: $eveningHour,
                playReminderOnSpeaker: $playReminderOnSpeaker
            )
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if let titleText {
            Text(titleText)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var titleText: String? {
        switch phase {
        case .preparing, .exitingAfterSchedule:
            return phase == .exitingAfterSchedule
                ? AppLanguage.text(lt: "Baigiama…", en: "Finishing…")
                : AppLanguage.text(lt: "Ruošiama…", en: "Preparing…")
        case .recording:
            return AppLanguage.text(lt: "Įrašoma", en: "Recording")
        case .chooseWhen:
            return AppLanguage.text(lt: "Kada priminti?", en: "When to remind?")
        case .playback:
            return nil
        case .needsSettings:
            return AppLanguage.text(lt: "Reikia leidimų", en: "Permissions needed")
        }
    }

    private var recordingCircle: some View {
        VStack(spacing: 22) {
            AnalogLevelMeter(level: recorder.meteringLevel)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.85), Color.orange.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(recordingPulse ? 1.06 : 1.0)
                    .animation(
                        recordingPulse ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : .default,
                        value: recordingPulse
                    )

                Text(AppLanguage.text(lt: "Baigti įrašą", en: "Stop recording"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
        .onTapGesture {
            Task { await finishRecording() }
        }
        .accessibilityLabel(AppLanguage.text(lt: "Baigti įrašą", en: "Stop recording"))
    }

    private var chooseWhenSection: some View {
        VStack(spacing: 12) {
            HStack {
                Picker(AppLanguage.text(lt: "Kartoti", en: "Repeat"), selection: $repeatMode) {
                    ForEach(RepeatMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    showTimeSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(AppLanguage.text(lt: "Laikų nustatymai", en: "Time settings"))
            }

            soundPickerRow

            if repeatMode == .custom {
                weekdayPicker
                repeatTimeRow
                if showCustomRepeatTime {
                    customRepeatTimeSection
                }
            }

            if repeatMode == .once && !showCustomDate {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLanguage.text(lt: "Šiandien", en: "Today"))
                            .font(.headline)

                        HStack(spacing: 8) {
                            quickTodayButton(hours: 1)
                            quickTodayButton(hours: 3)
                            quickTodayButton(hours: 5)
                        }
                    }

                    ForEach(DayPreset.allCases, id: \.rawValue) { preset in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preset.title)
                                .font(.headline)

                            HStack(spacing: 8) {
                                ForEach(DayPeriod.allCases, id: \.rawValue) { period in
                                    Button {
                                        Task { await schedule(preset: preset, period: period) }
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text(period.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(timeLabel(for: period))
                                                .font(.caption2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(tint(for: period))
                                    .disabled(isBusy)
                                }
                            }
                        }
                    }
                }
            }

            if repeatMode == .once {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCustomDate.toggle()
                        if showCustomDate {
                            customRemindAt = max(
                                Date().addingTimeInterval(120),
                                Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                            )
                        }
                    }
                } label: {
                    Text(showCustomDate
                         ? AppLanguage.text(lt: "Slėpti datą ir laiką", en: "Hide date and time")
                         : AppLanguage.text(lt: "Pagal datą ir laiką", en: "Date and time"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isBusy)
            }

            if showCustomDate {
                DatePicker(
                    AppLanguage.text(lt: "Data ir laikas", en: "Date and time"),
                    selection: $customRemindAt,
                    in: Date().addingTimeInterval(60)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale.current)

                Button {
                    Task { await scheduleAt(customRemindAt) }
                } label: {
                    Text(AppLanguage.text(lt: "Suplanuoti", en: "Schedule"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)
            }

            Button(role: .cancel) {
                cancelRecordedReminder()
            } label: {
                Text(AppLanguage.text(lt: "Uždaryti", en: "Close"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isBusy)
        }
    }

    private func quickTodayButton(hours: Int) -> some View {
        Button {
            Task { await scheduleAt(Date().addingTimeInterval(Double(hours) * 60 * 60)) }
        } label: {
            Text(
                AppLanguage.text(
                    lt: "Po \(hours) val.",
                    en: hours == 1 ? "In 1 hr" : "In \(hours) hr"
                )
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(isBusy)
    }

    private var repeatTimeRow: some View {
        HStack(spacing: 8) {
            ForEach(DayPeriod.allCases, id: \.rawValue) { period in
                Button {
                    Task { await scheduleRepeating(period: period) }
                } label: {
                    VStack(spacing: 2) {
                        Text(period.title)
                            .font(.caption.weight(.semibold))
                        Text(timeLabel(for: period))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint(for: period))
                .disabled(isBusy)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCustomRepeatTime.toggle()
                    if showCustomRepeatTime {
                        customRepeatTime = timeAnchor
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text(AppLanguage.text(lt: "Pagal", en: "By"))
                        .font(.caption.weight(.semibold))
                    Text(AppLanguage.text(lt: "laiką", en: "time"))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
    }

    private var customRepeatTimeSection: some View {
        VStack(spacing: 10) {
            DatePicker(
                AppLanguage.text(lt: "Laikas", en: "Time"),
                selection: $customRepeatTime,
                displayedComponents: [.hourAndMinute]
            )
            .datePickerStyle(.compact)
            .environment(\.locale, Locale.current)

            Button {
                Task { await scheduleRepeating(at: customRepeatTime) }
            } label: {
                Text(AppLanguage.text(lt: "Kartoti šiuo laiku", en: "Repeat at this time"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
        }
    }

    private var soundPickerRow: some View {
        HStack(spacing: 10) {
            Label(AppLanguage.text(lt: "Garsas", en: "Sound"), systemImage: "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Menu {
                ForEach(NotificationSoundOption.allCases) { option in
                    Button {
                        notificationSoundName = option.rawValue
                        soundPreviewer.play(option)
                    } label: {
                        if selectedNotificationSound == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text(selectedNotificationSound.title)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 2)
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.text(lt: "Savaitės dienos", en: "Weekdays"))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(weekdayOptions, id: \.number) { day in
                    Button {
                        if selectedWeekdays.contains(day.number) {
                            selectedWeekdays.remove(day.number)
                        } else {
                            selectedWeekdays.insert(day.number)
                        }
                    } label: {
                        Text(day.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedWeekdays.contains(day.number) ? .blue : .gray)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var needsSettingsSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(AppLanguage.text(
                lt: "Uždarykite programėlę ir bandykite vėl iš piktogramos, kai leidimai bus įjungti.",
                en: "Close the app and try again from the icon after permissions are enabled."
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var weekdayOptions: [(number: Int, title: String)] {
        [
            (2, AppLanguage.text(lt: "Pir", en: "Mon")),
            (3, AppLanguage.text(lt: "Ant", en: "Tue")),
            (4, AppLanguage.text(lt: "Tre", en: "Wed")),
            (5, AppLanguage.text(lt: "Ket", en: "Thu")),
            (6, AppLanguage.text(lt: "Pen", en: "Fri")),
            (7, AppLanguage.text(lt: "Šeš", en: "Sat")),
            (1, AppLanguage.text(lt: "Sek", en: "Sun"))
        ]
    }

    private var selectedNotificationSound: NotificationSoundOption {
        NotificationSoundOption.option(for: notificationSoundName)
    }

    private func hour(for period: DayPeriod) -> Int {
        switch period {
        case .morning:
            return morningHour
        case .afternoon:
            return afternoonHour
        case .evening:
            return eveningHour
        }
    }

    private func timeLabel(for period: DayPeriod) -> String {
        String(format: "%02d:00", hour(for: period))
    }

    private func tint(for period: DayPeriod) -> Color {
        switch period {
        case .morning:
            return .blue
        case .afternoon:
            return .orange
        case .evening:
            return .purple
        }
    }

    private func weekdaysForRepeatMode() -> [Int] {
        switch repeatMode {
        case .once:
            return []
        case .custom:
            return Array(selectedWeekdays).sorted()
        }
    }

    private func runLaunchFlow() async {
        for _ in 0..<12 {
            if let nid = playbackRouter.pendingNotificationId ?? playbackRouter.savedPendingNotificationId() {
                await MainActor.run {
                    openPlayback(notificationId: nid)
                }
                return
            }
            if let nid = ScheduledReminderPlayback.dueNotificationId() {
                await MainActor.run {
                    openPlayback(notificationId: nid)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        await startFreshSession()
    }

    private func openPlayback(notificationId: String) {
        if recorder.isRecording {
            recorder.stop()
        }
        isBusy = false
        showCustomDate = false
        phase = .playback(notificationId: notificationId)
        status = ""
        ReminderScheduler.cancelPendingAlerts(notificationId: notificationId)
        playbackRouter.clearIfCurrent(notificationId)
        ScheduledReminderPlayback.clearIfCurrent(notificationId)
    }

    private func snoozePlayback(notificationId: String, until date: Date) async {
        guard !isBusy else { return }
        await MainActor.run {
            isBusy = true
            phase = .exitingAfterSchedule
            status = ""
        }

        do {
            ReminderScheduler.cancelPendingAlerts(notificationId: notificationId)
            try await ReminderScheduler.snooze(notificationId: notificationId, until: date)
            let when = Self.dateFormatter.string(from: date)
            await MainActor.run {
                isBusy = false
                status = AppLanguage.text(lt: "Priminimas: \(when).", en: "Reminder: \(when).")
            }
            try await Task.sleep(nanoseconds: 550_000_000)
            exit(0)
        } catch {
            await MainActor.run {
                isBusy = false
                phase = .playback(notificationId: notificationId)
                status = AppLanguage.text(lt: "Nepavyko atidėti priminimo.", en: "Could not snooze the reminder.")
            }
        }
    }

    private func stopRepeating(notificationId: String) async {
        ReminderScheduler.cancelRepeating(notificationId: notificationId)
        await MainActor.run {
            phase = .exitingAfterSchedule
            status = AppLanguage.text(lt: "Kartojimas išjungtas.", en: "Repeat turned off.")
        }
        try? await Task.sleep(nanoseconds: 550_000_000)
        exit(0)
    }

    /// Kai naudotojas sąmoningai nori naujo įrašo iš „iš pranešimo“ ekrano.
    private func startNewRecordingFromNotificationScreen() async {
        await MainActor.run {
            phase = .preparing
            status = ""
            showCustomDate = false
            showCustomRepeatTime = false
        }
        await startFreshSession()
    }

    private func startFreshSession() async {
        await MainActor.run {
            phase = .preparing
            status = ""
            showCustomDate = false
            showCustomRepeatTime = false
            reminderTitle = ReminderTitleGenerator.fallbackTitle
            isBusy = false
        }

        let mic = await recorder.requestPermission()
        if !mic {
            await MainActor.run {
                status = AppLanguage.text(lt: "Įjunkite mikrofono leidimą nustatymuose.", en: "Enable microphone permission in Settings.")
                phase = .needsSettings
            }
            return
        }

        let notifGranted: Bool
        do {
            notifGranted = try await ReminderScheduler.requestAuthorization()
        } catch {
            await MainActor.run {
                status = AppLanguage.text(lt: "Nepavyko paprašyti pranešimų leidimo.", en: "Could not request notification permission.")
                phase = .needsSettings
            }
            return
        }

        if !notifGranted {
            await MainActor.run {
                status = AppLanguage.text(lt: "Įjunkite pranešimus nustatymuose.", en: "Enable notifications in Settings.")
                phase = .needsSettings
            }
            return
        }

        do {
            try await recorder.ensureMicPermission()
            try recorder.start()
            await MainActor.run {
                phase = .recording
                status = ""
            }
        } catch let error as VoiceRecorderError {
            await MainActor.run {
                status = error.localizedDescription
                phase = .needsSettings
            }
        } catch {
            await MainActor.run {
                status = AppLanguage.text(lt: "Nepavyko pradėti įrašymo.", en: "Could not start recording.")
                phase = .needsSettings
            }
        }
    }

    private func finishRecording() async {
        guard !isBusy, recorder.isRecording else { return }
        isBusy = true
        defer { isBusy = false }

        let fileURL = await recorder.stopAndWaitForFile()
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            await MainActor.run {
                status = AppLanguage.text(lt: "Įrašo failas nesukurtas.", en: "Recording file was not created.")
                phase = .needsSettings
            }
            return
        }
        guard VoiceRecorder.canOpenForPlayback(fileURL) else {
            await MainActor.run {
                status = AppLanguage.text(
                    lt: "iPhone nepavyko paruošti įrašo perklausai. Bandykite įrašyti dar kartą.",
                    en: "iPhone could not prepare the recording for playback. Try recording again."
                )
                phase = .needsSettings
            }
            return
        }
        await MainActor.run {
            status = AppLanguage.text(lt: "Kuriamas pavadinimas…", en: "Creating title…")
        }
        let generatedTitle = await ReminderTitleGenerator.title(from: fileURL)

        await MainActor.run {
            reminderTitle = generatedTitle
            timeAnchor = Date()
            phase = .chooseWhen
            status = generatedTitle == ReminderTitleGenerator.fallbackTitle
                ? AppLanguage.text(lt: "Pasirinkite, kada gauti priminimą.", en: "Choose when to be reminded.")
                : AppLanguage.text(lt: "Pavadinimas: \(generatedTitle)", en: "Title: \(generatedTitle)")
        }
    }

    private func cancelRecordedReminder() {
        if recorder.isRecording {
            recorder.stop()
        }
        if let fileURL = recorder.currentFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        phase = .exitingAfterSchedule
        status = AppLanguage.text(lt: "Įrašas ištrintas.", en: "Recording deleted.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(0)
        }
    }

    private func schedule(preset: DayPreset, period: DayPeriod) async {
        if repeatMode != .once {
            await scheduleRepeating(period: period)
            return
        }

        let date = SchedulingTime.onNthDayFromToday(
            offsetDays: preset.rawValue,
            hour: hour(for: period),
            minute: 0,
            today: Date()
        )
        guard let date else {
            await MainActor.run {
                status = AppLanguage.text(lt: "Nepavyko apskaičiuoti datos.", en: "Could not calculate the date.")
            }
            return
        }
        await scheduleAt(date)
    }

    private func scheduleRepeating(period: DayPeriod) async {
        await scheduleRepeating(hour: hour(for: period), minute: 0, label: timeLabel(for: period))
    }

    private func scheduleRepeating(at date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        await scheduleRepeating(hour: hour, minute: minute, label: String(format: "%02d:%02d", hour, minute))
    }

    private func scheduleRepeating(hour: Int, minute: Int, label: String) async {
        guard !isBusy else { return }
        guard let fileURL = recorder.currentFileURL else {
            await MainActor.run {
                status = AppLanguage.text(lt: "Nėra įrašo failo.", en: "No recording file.")
                phase = .needsSettings
            }
            return
        }

        let weekdays = weekdaysForRepeatMode()
        guard !weekdays.isEmpty else {
            await MainActor.run {
                status = AppLanguage.text(lt: "Pasirinkite bent vieną savaitės dieną.", en: "Choose at least one weekday.")
            }
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await ReminderScheduler.scheduleRepeating(
                weekdays: weekdays,
                hour: hour,
                minute: minute,
                voiceFileURL: fileURL,
                title: reminderTitle,
                soundName: selectedNotificationSound.notificationSoundName
            )
            await MainActor.run {
                phase = .exitingAfterSchedule
                status = AppLanguage.text(lt: "Kartojamas priminimas: \(label).", en: "Repeating reminder: \(label).")
            }
            try await Task.sleep(nanoseconds: 550_000_000)
            exit(0)
        } catch {
            await MainActor.run {
                status = error.localizedDescription
            }
        }
    }

    private func scheduleAt(_ date: Date) async {
        guard !isBusy else { return }
        guard let fileURL = recorder.currentFileURL else {
            await MainActor.run {
                status = AppLanguage.text(lt: "Nėra įrašo failo.", en: "No recording file.")
                phase = .needsSettings
            }
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await ReminderScheduler.schedule(
                at: date,
                voiceFileURL: fileURL,
                title: reminderTitle,
                soundName: selectedNotificationSound.notificationSoundName
            )
            let when = Self.dateFormatter.string(from: date)
            await MainActor.run {
                phase = .exitingAfterSchedule
                status = AppLanguage.text(lt: "Priminimas: \(when).", en: "Reminder: \(when).")
            }
            // Trumpas patvirtinimas, tada išėjimas (Apple rekomenduoja ne naudoti exit – čia sąmoningai pagal pageidavimą).
            try await Task.sleep(nanoseconds: 550_000_000)
            exit(0)
        } catch {
            await MainActor.run {
                status = error.localizedDescription
            }
        }
    }
}

private struct AnalogLevelMeter: View {
    let level: CGFloat

    private var clampedLevel: CGFloat {
        min(max(level, 0), 1)
    }

    private var needleAngle: Angle {
        .degrees(Double(-47 + clampedLevel * 94))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.96, green: 0.98, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.91, green: 0.98, blue: 1.00),
                            Color(red: 0.72, green: 0.92, blue: 1.00),
                            Color(red: 0.96, green: 0.99, blue: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 238, height: 112)
                .offset(y: -12)
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                        Path { path in
                            path.move(to: CGPoint(x: 74, y: 2))
                            path.addLine(to: CGPoint(x: 122, y: 2))
                            path.addLine(to: CGPoint(x: 94, y: 102))
                            path.addLine(to: CGPoint(x: 34, y: 102))
                            path.closeSubpath()
                        }
                        .fill(Color.white.opacity(0.46))
                        .frame(width: 238, height: 112)
                    }
                    .offset(y: -12)
                )

            VUMeterScale()
                .offset(y: -12)

            Text("VU")
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundStyle(.black.opacity(0.72))
                .offset(y: 4)

            Rectangle()
                .fill(Color.black.opacity(0.84))
                .frame(width: 3, height: 96)
                .offset(y: 24)
                .rotationEffect(needleAngle, anchor: .bottom)
                .animation(.easeOut(duration: 0.08), value: clampedLevel)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.82, green: 0.89, blue: 0.93)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.black.opacity(0.22), lineWidth: 1))
                .offset(y: 64)
        }
        .frame(width: 270, height: 158)
        .accessibilityLabel(AppLanguage.text(lt: "Garso indikatorius", en: "Sound meter"))
    }
}

private struct VUMeterScale: View {
    private let startAngle = 205.0
    private let endAngle = 335.0
    private let center = CGPoint(x: 130, y: 130)
    private let radius: CGFloat = 106

    var body: some View {
        ZStack {
            VUMeterArc(startAngle: startAngle, endAngle: 294, center: center, radius: radius)
                .stroke(Color.black.opacity(0.68), lineWidth: 2)
            VUMeterArc(startAngle: 294, endAngle: endAngle, center: center, radius: radius)
                .stroke(Color(red: 0.76, green: 0.0, blue: 0.17).opacity(0.88), lineWidth: 2)

            ForEach(0...22, id: \.self) { index in
                let progress = Double(index) / 22
                let angle = startAngle + (endAngle - startAngle) * progress
                let isMajor = index % 2 == 0
                let isRed = index <= 3 || index >= 18
                VUMeterTick(angle: angle, center: center, radius: radius, length: isMajor ? 14 : 8)
                    .stroke(isRed ? Color(red: 0.76, green: 0.0, blue: 0.17).opacity(0.88) : Color.black.opacity(0.68), lineWidth: isMajor ? 2 : 1)
            }

            ForEach(labels.indices, id: \.self) { index in
                let label = labels[index]
                Text(label.text)
                    .font(.system(size: label.small ? 8 : 11, weight: .medium, design: .serif))
                    .foregroundStyle(label.red ? Color(red: 0.76, green: 0.0, blue: 0.17).opacity(0.88) : Color.black.opacity(0.68))
                    .position(point(for: label.angle, radius: label.radius))
            }
        }
        .frame(width: 260, height: 150)
    }

    private var labels: [(text: String, angle: Double, radius: CGFloat, red: Bool, small: Bool)] {
        [
            ("20", 212, 82, true, false),
            ("10", 235, 78, false, false),
            ("7", 248, 76, false, false),
            ("5", 262, 76, false, false),
            ("3", 278, 76, false, false),
            ("1", 296, 76, false, false),
            ("0", 308, 76, false, false),
            ("1", 321, 76, false, false),
            ("3", 333, 78, true, false),
            ("+5", 344, 82, true, false)
        ]
    }

    private func point(for angle: Double, radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

private struct VUMeterArc: Shape {
    let startAngle: Double
    let endAngle: Double
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

private struct VUMeterTick: Shape {
    let angle: Double
    let center: CGPoint
    let radius: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let radians = angle * .pi / 180
        let outer = CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
        let inner = CGPoint(
            x: center.x + cos(radians) * (radius - length),
            y: center.y + sin(radians) * (radius - length)
        )
        var path = Path()
        path.move(to: inner)
        path.addLine(to: outer)
        return path
    }
}

private struct ReminderTimeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var iconChanger = AppIconChanger()
    @Binding var morningHour: Int
    @Binding var afternoonHour: Int
    @Binding var eveningHour: Int
    @Binding var playReminderOnSpeaker: Bool

    var body: some View {
        VStack(spacing: 22) {
            Text(AppLanguage.text(lt: "Laikų nustatymai", en: "Time settings"))
                .font(.title2.weight(.semibold))

            hourStepper(AppLanguage.text(lt: "Rytas", en: "Morning"), value: $morningHour)
            hourStepper(AppLanguage.text(lt: "Diena", en: "Afternoon"), value: $afternoonHour)
            hourStepper(AppLanguage.text(lt: "Vakaras", en: "Evening"), value: $eveningHour)

            Toggle(isOn: $playReminderOnSpeaker) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguage.text(lt: "Perklausyti garsiakalbiu", en: "Play on speaker"))
                    Text(AppLanguage.text(
                        lt: "Išjungus, atidarytas priminimas po 2 s gros prie ausies.",
                        en: "Turn off to play near your ear 2 s after opening."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack(spacing: 10) {
                Label(AppLanguage.text(lt: "Ikona", en: "Icon"), systemImage: "app.fill")
                Spacer()
                Menu {
                    ForEach(AppIconOption.allCases) { option in
                        Button {
                            iconChanger.select(option)
                            dismiss()
                            Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                await MainActor.run {
                                    iconChanger.applyPendingChange()
                                }
                            }
                        } label: {
                            if iconChanger.current == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Text(iconChanger.current.title)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if let message = iconChanger.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                dismiss()
            } label: {
                Text(AppLanguage.text(lt: "Uždaryti", en: "Close"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    private func hourStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...23) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%02d:00", value.wrappedValue))
                    .font(.headline.monospacedDigit())
            }
        }
    }
}

#Preview {
    ContentView()
}

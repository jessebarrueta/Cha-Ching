import SwiftUI
import UIKit

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    var occurrenceId: UUID

    @State private var isSubmittingWithoutPhoto = false

    private var occurrence: TaskOccurrence? {
        store.occurrences.first { $0.id == occurrenceId }
    }

    var body: some View {
        Group {
            if let occurrence {
                let chore = store.chore(for: occurrence)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        taskHero(chore: chore)

                        VStack(spacing: 12) {
                            detailMetric(title: "Keep", value: "No deduction", color: .acidLime)
                            detailMetric(title: "Miss it", value: Money.dollars(-chore.deductionCents, signed: true), color: .warmOrange)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("What to do")
                                .font(.headline.weight(.heavy))
                            Text(chore.instructions)
                                .font(.body)
                                .foregroundStyle(Color.inkBlack)

                            Divider()

                            Text("Evidence tip")
                                .font(.headline.weight(.heavy))
                            Text(chore.expectedEvidence)
                                .font(.body)
                                .foregroundStyle(Color.mutedGray)
                        }
                        .cardSurface()

                        if store.allowsPhotoEvidence(for: chore) {
                            NavigationLink {
                                CameraCaptureView(occurrenceId: occurrence.id)
                            } label: {
                                Label("Take Photo", systemImage: "camera.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .foregroundStyle(Color.paperWhite)
                                    .background(Color.inkBlack, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if store.allowsNoPhotoSubmission(for: chore) {
                            Button {
                                Task {
                                    await submitWithoutPhoto()
                                }
                            } label: {
                                Label(
                                    occurrence.status == .submitted ? "Submitted" : "Submit Done",
                                    systemImage: occurrence.status == .submitted ? "checkmark.circle.fill" : "checkmark.circle"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .foregroundStyle(Color.inkBlack)
                                .background(Color.acidLime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isSubmittingWithoutPhoto || !occurrence.status.isOpen)
                        }

                        Button {
                            store.requestExcuse(occurrence)
                        } label: {
                            Text("I can't do this")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Color.mutedGray)
                        }
                        .accessibilityHint("Sends a parent review request")
                    }
                    .padding(22)
                }
                .background(Color.paperWhite.ignoresSafeArea())
                .navigationTitle("Task Detail")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Task not found", systemImage: "questionmark.circle")
            }
        }
    }

    private func submitWithoutPhoto() async {
        guard !isSubmittingWithoutPhoto else {
            return
        }

        isSubmittingWithoutPhoto = true
        await store.submitWithoutPhoto(for: occurrenceId)
        isSubmittingWithoutPhoto = false
    }

    private func taskHero(chore: ChoreDefinition) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.sunYellow, .sunYellow.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                dogIllustration
                    .frame(width: 138, height: 112)

                Text(chore.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.inkBlack)

                Text("Every day · Due by \(chore.dueTime)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkBlack.opacity(0.76))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)

            OrangeBlob()
                .fill(Color.warmOrange)
                .frame(width: 70, height: 58)
                .offset(x: 10, y: 12)
        }
        .frame(minHeight: 236)
    }

    private var dogIllustration: some View {
        ZStack {
            Circle()
                .fill(Color.paperWhite)
                .frame(width: 96, height: 86)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.90, green: 0.68, blue: 0.36))
                .frame(width: 32, height: 68)
                .rotationEffect(.degrees(22))
                .offset(x: -42, y: 2)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.22, green: 0.14, blue: 0.08))
                .frame(width: 32, height: 68)
                .rotationEffect(.degrees(-22))
                .offset(x: 42, y: 2)

            VStack(spacing: 7) {
                HStack(spacing: 26) {
                    Circle().fill(Color.inkBlack).frame(width: 7, height: 7)
                    Circle().fill(Color.inkBlack).frame(width: 7, height: 7)
                }
                Capsule()
                    .fill(Color.inkBlack)
                    .frame(width: 14, height: 10)
                ArcSmile()
                    .stroke(Color.inkBlack, lineWidth: 2)
                    .frame(width: 28, height: 12)
            }
            .offset(y: 8)
        }
    }

    private func detailMetric(title: String, value: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.mutedGray)
                Text(value)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(color)
            }
            Spacer()
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.softGray, lineWidth: 1)
        )
    }
}

struct CameraCaptureView: View {
    @EnvironmentObject private var store: AppStore
    var occurrenceId: UUID

    @State private var capturedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var isSubmitting = false

    private var occurrence: TaskOccurrence? {
        store.occurrences.first { $0.id == occurrenceId }
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        if let occurrence, occurrence.status == .aiReviewed {
            AIReviewResultView(occurrenceId: occurrenceId)
        } else {
            cameraSurface
        }
    }

    private var cameraSurface: some View {
        ZStack {
            Color.inkBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                photoSurface
                    .overlay(framingGuides)
                    .overlay {
                        if isSubmitting {
                            ZStack {
                                Color.black.opacity(0.28)
                                ProgressView()
                                    .tint(Color.paperWhite)
                                    .scaleEffect(1.4)
                            }
                        }
                    }

                VStack(spacing: 20) {
                    HStack {
                        CircleButton(systemImage: "bolt.fill")
                        Spacer()
                        Button {
                            captureTapped()
                        } label: {
                            Circle()
                                .stroke(Color.paperWhite, lineWidth: 4)
                                .frame(width: 78, height: 78)
                                .overlay {
                                    Circle()
                                        .fill(Color.paperWhite)
                                        .frame(width: 62, height: 62)
                                }
                        }
                        .disabled(isSubmitting)
                        .accessibilityLabel("Capture photo")
                        Spacer()
                        CircleButton(systemImage: "arrow.triangle.2.circlepath.camera.fill")
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.sunYellow)
                        Text("Show the full task area clearly.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.inkBlack)
                        Spacer()
                        LimeMascot()
                            .frame(width: 56, height: 60)
                            .clipped()
                    }
                    .padding(16)
                    .background(Color.paperWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(22)
            }
        }
        .navigationTitle("Take a Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.inkBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraImagePicker { image in
                capturedImage = image
                Task {
                    await submitCapturedImage(image)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var mockPhoto: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.74, green: 0.70, blue: 0.64),
                    Color(red: 0.47, green: 0.42, blue: 0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                ZStack {
                    Ellipse()
                        .fill(Color.paperWhite)
                        .frame(width: 190, height: 74)
                    Ellipse()
                        .fill(Color(red: 0.22, green: 0.13, blue: 0.07))
                        .frame(width: 150, height: 46)
                    HStack(spacing: 6) {
                        ForEach(0..<12, id: \.self) { index in
                            Circle()
                                .fill(Color(red: 0.43, green: 0.24, blue: 0.08))
                                .frame(width: CGFloat(10 + (index % 3) * 3), height: CGFloat(10 + (index % 3) * 3))
                        }
                    }
                    .frame(width: 130)
                }

                HStack(spacing: 22) {
                    ForEach(0..<3, id: \.self) { _ in
                        Image(systemName: "pawprint.fill")
                            .font(.title)
                            .foregroundStyle(Color.inkBlack.opacity(0.75))
                    }
                }
            }
            .offset(y: 70)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 470)
        .clipped()
    }

    @ViewBuilder
    private var photoSurface: some View {
        if let capturedImage {
            Image(uiImage: capturedImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 470)
                .clipped()
        } else {
            mockPhoto
        }
    }

    private func captureTapped() {
        guard !isSubmitting else {
            return
        }

        if cameraAvailable {
            isShowingCamera = true
        } else {
            Task {
                await submitCapturedImage(nil)
            }
        }
    }

    private func submitCapturedImage(_ image: UIImage?) async {
        isSubmitting = true
        defer { isSubmitting = false }

        let jpegData = image?.evidenceJPEGData()
        await store.submitEvidence(for: occurrenceId, jpegData: jpegData)
    }

    private var framingGuides: some View {
        GeometryReader { proxy in
            let guideSize: CGFloat = 44
            let lineWidth: CGFloat = 4

            ZStack {
                GuideCorner()
                    .stroke(Color.sunYellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: guideSize, height: guideSize)
                    .position(x: 48, y: 108)

                GuideCorner()
                    .stroke(Color.sunYellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: guideSize, height: guideSize)
                    .position(x: proxy.size.width - 48, y: 108)

                GuideCorner()
                    .stroke(Color.sunYellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(270))
                    .frame(width: guideSize, height: guideSize)
                    .position(x: 48, y: proxy.size.height - 68)

                GuideCorner()
                    .stroke(Color.sunYellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(180))
                    .frame(width: guideSize, height: guideSize)
                    .position(x: proxy.size.width - 48, y: proxy.size.height - 68)
            }
        }
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private extension UIImage {
    func evidenceJPEGData(maxDimension: CGFloat = 1600, compressionQuality: CGFloat = 0.82) -> Data? {
        let longestSide = max(size.width, size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalizedImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return normalizedImage.jpegData(compressionQuality: compressionQuality)
    }
}

struct AIReviewResultView: View {
    @EnvironmentObject private var store: AppStore
    var occurrenceId: UUID

    private var occurrence: TaskOccurrence? {
        store.occurrences.first { $0.id == occurrenceId }
    }

    var body: some View {
        let submission = occurrence.flatMap { store.submission(for: $0) }
        let result = submission?.aiResult
        let confidence = Int((result?.confidence ?? 0) * 100)

        VStack(spacing: 26) {
            Spacer(minLength: 8)

            ZStack {
                LimeMascot()
                FloatingShapes()
            }

            VStack(spacing: 10) {
                Text(result?.retakeSuggested == true ? "Try another photo" : "Looks good!")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text(result?.reason ?? "Our AI saved the submission for parent review.")
                    .font(.body)
                    .foregroundStyle(Color.mutedGray)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Confidence")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.mutedGray)
                Text("\(confidence)%")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
                CapsuleProgress(value: Double(confidence) / 100)
                    .tint(.green)
            }
            .cardSurface()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock")
                    .font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pending parent review")
                        .font(.headline)
                    Text("AI is advisory. A parent has the final say.")
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedGray)
                }
                Spacer()
            }
            .padding(.horizontal, 6)

            Spacer()

            NavigationLink {
                DashboardView()
            } label: {
                Text("Back to Today")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(Color.paperWhite)
                    .background(Color.inkBlack, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(Color.paperWhite.ignoresSafeArea())
        .navigationTitle("AI Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CircleButton: View {
    var systemImage: String

    var body: some View {
        Button {
        } label: {
            Circle()
                .fill(Color.black.opacity(0.42))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(Color.paperWhite)
                }
        }
        .buttonStyle(.plain)
    }
}

struct GuideCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct FloatingShapes: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.sunYellow).frame(width: 18, height: 18).offset(x: 100, y: 18)
            BlueTriangle().fill(Color.electricBlue).frame(width: 16, height: 14).offset(x: -96, y: 48)
            BlueTriangle().fill(Color.hotPink).frame(width: 18, height: 16).rotationEffect(.degrees(35)).offset(x: 92, y: -62)
            BlueTriangle().fill(Color.warmOrange).frame(width: 18, height: 16).rotationEffect(.degrees(-24)).offset(x: -84, y: -64)
        }
        .frame(width: 260, height: 200)
        .accessibilityHidden(true)
    }
}

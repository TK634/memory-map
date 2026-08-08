import SwiftUI

/// 全画面の写真ビューア(スワイプで送る・ピンチで拡大・共有・削除)
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UIImage]
    let captions: [String?]
    @State var index: Int
    var onDelete: ((Int) -> Void)?

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var showChrome = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(i == index ? scale : 1)
                        .offset(i == index ? offset : .zero)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = max(1, $0) }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.3)) {
                                        if scale < 1.1 { scale = 1; offset = .zero }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { if scale > 1 { offset = $0.translation } }
                                .onEnded { _ in
                                    if scale <= 1 { withAnimation { offset = .zero } }
                                }
                        )
                        .tag(i)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { showChrome.toggle() }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if showChrome {
                VStack {
                    // 上部: 閉じる・枚数
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                        Spacer()
                        if images.count > 1 {
                            Text("\(index + 1) / \(images.count)")
                                .font(.footnote.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.black.opacity(0.4), in: Capsule())
                        }
                        Spacer()
                        Menu {
                            if let onDelete {
                                Button(role: .destructive) {
                                    let target = index
                                    if index >= images.count - 1 { index = max(0, index - 1) }
                                    onDelete(target)
                                    if images.count <= 1 { dismiss() }
                                } label: { Label("この写真を削除", systemImage: "trash") }
                            }
                            ShareLink(item: Image(uiImage: images[min(index, images.count - 1)]),
                                      preview: SharePreview("あしあとの写真",
                                                            image: Image(uiImage: images[min(index, images.count - 1)]))) {
                                Label("共有・保存", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                    // 下部: キャプション
                    if index < captions.count, let cap = captions[index], !cap.isEmpty {
                        Text(cap)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.4))
                    }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden()
    }
}

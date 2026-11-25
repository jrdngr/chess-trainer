import Game
import Model
import StoreKit
import SwiftUI

/// The App Store side of cash purchases: the products' prices, buying, and every transaction
/// handed to the model to credit once, including ones finished elsewhere (another device,
/// Ask to Buy, a reinstall) and the unlock already owned.
@Observable @MainActor
final class CashStore {
  /// The products the App Store offers, by id; empty until they load, or where it offers none.
  private(set) var products: [CashProduct: Product] = [:]
  /// The product being bought.
  private(set) var buying: CashProduct?
  /// Whether the products are being asked for.
  private(set) var loading = false
  @ObservationIgnored private weak var store: Game.AppStore?
  @ObservationIgnored private var updates: Task<Void, Never>?

  /// Start once the saved state is loaded: listen for transactions, load the prices, and credit the unlock if owned.
  func start(_ store: Game.AppStore) async {
    self.store = store
    if updates == nil {
      updates = Task { [weak self] in
        for await result in StoreKit.Transaction.updates { await self?.handle(result, bought: false) }
      }
    }
    await loadProducts()
    await restore()
  }

  /// Ask the App Store for the products, unless it has already given them or is being asked.
  func loadProducts() async {
    guard products.isEmpty, !loading else { return }
    loading = true
    defer { loading = false }
    if let found = try? await Product.products(for: CashProduct.allCases.map(\.rawValue)) {
      for product in found { if let id = CashProduct(rawValue: product.id) { products[id] = product } }
    }
  }

  /// Buy a product. Returns whether it was bought and credited.
  @discardableResult
  func buy(_ product: CashProduct) async -> Bool {
    guard let item = products[product], buying == nil else { return false }
    buying = product
    defer { buying = nil }
    guard case .success(let result) = try? await item.purchase() else { return false }
    return await handle(result, bought: true)
  }

  /// The unlock, when the App Store says it is owned: credited to the profile open now.
  func restore() async {
    for await result in StoreKit.Transaction.currentEntitlements { await handle(result, bought: false) }
  }

  /// Restore purchases: sync with the App Store first, which may ask the player to sign in.
  func syncAndRestore() async {
    try? await StoreKit.AppStore.sync()
    await restore()
  }

  /// Credits a transaction, or takes back a refunded one, and finishes it with the App Store
  /// once that is saved. One not saved stays unfinished, so the App Store hands it back later.
  @discardableResult
  private func handle(_ result: VerificationResult<StoreKit.Transaction>, bought: Bool) async -> Bool {
    guard case .verified(let transaction) = result, let store else { return false }
    var credited = false
    if let product = CashProduct(rawValue: transaction.productID) {
      if transaction.revocationDate == nil {
        credited = store.credit(product, transaction: String(transaction.id), bought: bought)
      } else {
        store.revoke(product, transaction: String(transaction.id))
      }
    }
    guard store.savesKept else { return credited }
    await transaction.finish()
    return credited
  }
}

/// The pawn sheet: the $10 unlock until the tree is yours, the pawn packs, and Restore
/// purchases. Opened from the pawn balance and from a price you can't pay yet.
struct PawnSheet: View {
  let onClose: () -> Void
  @Environment(Game.AppStore.self) private var store
  @Environment(CashStore.self) private var cash
  @Environment(Toasts.self) private var toasts

  var body: some View {
    let packs = CashProduct.packs.compactMap { pack in cash.products[pack].map { (pack, $0) } }
    VStack(spacing: 14) {
      ZStack {
        Text("Pawns").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
        HStack {
          Button(action: onClose) {
            Icon(name: "close", size: 19).foregroundStyle(Theme.text).frame(width: 37, height: 37)
              .background(Circle().fill(Theme.surface2))
          }
          .buttonStyle(.plain).accessibilityLabel("Close")
          Spacer()
        }
      }
      .frame(height: 56).padding(.horizontal, 4)
      if let product = cash.products[.unlock], !store.state.ownsUnlockItems {
        HStack(spacing: 12) {
          Icon(name: "star", size: 20).foregroundStyle(Theme.accent)
          Text("Unlock everything").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
          Spacer(minLength: 0)
          Button { Task { await cash.buy(.unlock) } } label: { Text(product.displayPrice) }
            .buttonStyle(PlayButtonStyle(kind: .accent, height: 40, inset: 14))
            .disabled(cash.buying != nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
      }
      if !packs.isEmpty {
        HStack(spacing: 8) {
          ForEach(packs, id: \.0) { pack, product in
            Button {
              Task {
                if await cash.buy(pack) {
                  // The sheet closes, so the balance and the toast are in view.
                  onClose()
                  toasts.show("\(pack.pawns.formatted()) pawns added")
                }
              }
            } label: {
              VStack(spacing: 6) {
                PawnAmount(count: pack.pawns, size: 15)
                Text(product.displayPrice).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
              }
              .frame(maxWidth: .infinity, minHeight: 64)
              .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
              .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(cash.buying != nil)
          }
        }
      } else if cash.loading {
        ProgressView().frame(minHeight: 64)
      }
      Button { Task { await cash.syncAndRestore() } } label: {
        Text("Restore purchases").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text3)
          .frame(minHeight: 36)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
    .task { await cash.loadProducts() }
  }
}

extension View {
  /// The pawn sheet, sized to what it holds.
  func pawnSheet(isPresented: Binding<Bool>) -> some View {
    modifier(PawnSheetPresenter(isPresented: isPresented))
  }
}

private struct PawnSheetPresenter: ViewModifier {
  @Binding var isPresented: Bool
  @State private var height: CGFloat = 260

  func body(content: Content) -> some View {
    content.sheet(isPresented: $isPresented) {
      PawnSheet { isPresented = false }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationBackground(SwiftUI.Color(hex: 0x131317))
    }
  }
}

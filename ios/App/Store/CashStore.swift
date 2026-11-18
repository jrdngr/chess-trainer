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
    if let found = try? await Product.products(for: CashProduct.allCases.map(\.rawValue)) {
      for product in found { if let id = CashProduct(rawValue: product.id) { products[id] = product } }
    }
    await restore()
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

  @discardableResult
  private func handle(_ result: VerificationResult<StoreKit.Transaction>, bought: Bool) async -> Bool {
    guard case .verified(let transaction) = result else { return false }
    var credited = false
    if transaction.revocationDate == nil, let product = CashProduct(rawValue: transaction.productID), let store {
      credited = store.credit(product, transaction: String(transaction.id), bought: bought)
    }
    await transaction.finish()
    return credited
  }
}

/// The $10 unlock, above the shop's tree until it is yours.
struct UnlockEverythingRow: View {
  @Environment(Game.AppStore.self) private var store
  @Environment(CashStore.self) private var cash

  var body: some View {
    if let product = cash.products[.unlock], !store.state.ownsFeatureTree {
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
  }
}

/// Pawn packs, and Restore purchases, under the tree.
struct PawnPacksRow: View {
  @Environment(CashStore.self) private var cash
  @Environment(Toasts.self) private var toasts

  var body: some View {
    let packs = CashProduct.packs.compactMap { pack in cash.products[pack].map { (pack, $0) } }
    VStack(spacing: 10) {
      if !packs.isEmpty {
        HStack(spacing: 8) {
          ForEach(packs, id: \.0) { pack, product in
            Button {
              Task { if await cash.buy(pack) { toasts.show("\(pack.pawns.formatted()) pawns added") } }
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
      }
      Button { Task { await cash.syncAndRestore() } } label: {
        Text("Restore purchases").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text3)
          .frame(minHeight: 36)
      }
      .buttonStyle(.plain)
    }
  }
}

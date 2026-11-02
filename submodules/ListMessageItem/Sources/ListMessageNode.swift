import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import AccountContext

public class ListMessageNode: ListViewItemNode {
    var item: ListMessageItem?
    var interaction: ListMessageItemInteraction?
    
    required init() {
        super.init(layerBacked: false)
    }
    
    func setupItem(_ item: ListMessageItem) {
        self.item = item
        // Rows carrying the locally archived copy of a deleted message are ghosted with the same
        // opacity ChatMessageItemView uses in the bubble layout, so a deleted message looks alike
        // in both list modes. Recomputed on every setup, so a reused node never keeps a stale
        // opacity.
        let archivedOpacity: CGFloat = 0.45
        self.alpha = item.isArchived ? archivedOpacity : 1.0
    }
    
    override public func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, neighbors: ListViewItemNeighbors) {
    }
    
    public func asyncLayout() -> (_ item: ListMessageItem, _ params: ListViewItemLayoutParams, _ mergedTop: Bool, _ mergedBottom: Bool, _ dateAtBottom: Bool) -> (ListViewItemNodeLayout, (ListViewItemUpdateAnimation) -> Void) {
        return { _, params, _, _, _ in
            return (ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 1.0), insets: UIEdgeInsets()), { _ in
                
            })
        }
    }
    
    public func transitionNode(id: EngineMessage.Id, media: EngineRawMedia, adjustRect: Bool) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        return nil
    }
    
    public func updateHiddenMedia() {
    }
    
    public func updateSelectionState(animated: Bool) {
    }
}

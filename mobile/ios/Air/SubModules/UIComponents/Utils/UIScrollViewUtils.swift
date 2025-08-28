//
//  UIScrollViewUtils.swift
//  MyTonWalletAir
//
//  Created by Sina on 12/17/24.
//

import UIKit

public extension UIScrollView {
   func scrollToBottom(animated: Bool) {
     if self.contentSize.height < self.bounds.size.height { return }
     let bottomOffset = CGPoint(x: 0, y: self.contentSize.height - self.bounds.size.height)
     self.setContentOffset(bottomOffset, animated: animated)
  }
}

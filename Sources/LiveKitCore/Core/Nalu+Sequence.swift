//
//  Nalu+Sequence.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 12/6/23.
//

import Foundation

public struct NaluSequence {
	
	@usableFromInline
	internal let base: Data
	
	@inlinable
	init(base: Data) {
		self.base = base
	}
}

extension NaluSequence {
	
	public struct Iterator {
		
		@usableFromInline
		internal let base: Data
		
		@usableFromInline
		internal var index: Data.Index
		
		@usableFromInline
		internal var previousNaluStartRange: Range<Data.Index>?
		
		@inlinable
		internal init(base: Data) {
			self.base = base
			self.index = base.startIndex
		}
	}
}

extension NaluSequence.Iterator: IteratorProtocol {
	
	public typealias Element = Nalu
	
	@inlinable
	public mutating func next() -> Element? {
		
		let lastIndex = base.endIndex.advanced(by: -1)
		
		while index < lastIndex {
			var nextNaluStartRange = base.firstRange(of: NaluType.naluShortStartSequence, in: (index..<lastIndex))
			
			if let nextRange = nextNaluStartRange, nextRange.lowerBound > base.startIndex {
				let beforeIndex = nextRange.lowerBound.advanced(by: -1)
				let beforeValue = base[beforeIndex]
				if beforeValue == 0 {
					nextNaluStartRange = (beforeIndex..<nextRange.upperBound)
				}
			}
			
			defer {
				previousNaluStartRange = nextNaluStartRange
				index = nextNaluStartRange?.upperBound ?? base.endIndex
			}
			
			guard let previousNaluStartRange else {
				continue
			}
			
			let naluRangeLowerBound = previousNaluStartRange.lowerBound
			let naluRangeUpperBound = nextNaluStartRange?.lowerBound ?? base.endIndex
			let naluRange = (naluRangeLowerBound..<naluRangeUpperBound)
			let naluData = base[naluRange]
			let nalu = Nalu(data: naluData, headerBytes: previousNaluStartRange.count)
			return nalu
		}
		
		guard let previousNaluStartRange else { return nil }
		
		let finalNaluRange = (previousNaluStartRange.lowerBound..<base.endIndex)
		let finalNaluData = base[finalNaluRange]
		let finalNalu = Nalu(data: finalNaluData, headerBytes: previousNaluStartRange.count)
		
		self.previousNaluStartRange = nil
		
		return finalNalu
	}
}

extension NaluSequence: Sequence {
	
	@inlinable
	public func makeIterator() -> NaluSequence.Iterator {
		NaluSequence.Iterator(base: self.base)
	}
	
	@inlinable
	public var underestimatedCount: Int {
		return 0
	}
}

extension Data {
	
	@usableFromInline
	func naluRange(start: Data.Index) -> Range<Index>? {
		
		guard count > 3 else { return nil }
		
		var previousResult: Range<Data.Index>?
		var currentIndex = start
		
		let lastIndex = endIndex.advanced(by: -3)
		while currentIndex < lastIndex {
			
			let nextIndex = currentIndex.advanced(by: 1)
			let twoNextIndex = currentIndex.advanced(by: 2)
			let naluKindIndex = twoNextIndex.advanced(by: 1)
			
			let currentValue = self[currentIndex]
			let nextValue = self[nextIndex]
			let nextNextValue = self[twoNextIndex]
			
			switch (currentValue, nextValue, nextNextValue) {
			case (_, 0, 0):
				currentIndex = nextIndex
				continue
				
			case (0, 0, 1):
				
				if let previousResult {
					return (previousResult.lowerBound..<naluKindIndex)
				} else {
					previousResult = (naluKindIndex..<endIndex)
					fallthrough
				}
				
			default:
				currentIndex = naluKindIndex
			}
		}
		return previousResult
	}
}

extension NaluSequence: LazySequenceProtocol {}

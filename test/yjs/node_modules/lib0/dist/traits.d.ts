export const EqualityTraitSymbol: unique symbol;
export type EqualityTrait = {
    [EqualityTraitSymbol]: (other: EqualityTrait) => boolean;
};
//# sourceMappingURL=traits.d.ts.map
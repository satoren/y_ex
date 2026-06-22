/**
 * @template V
 * @typedef {V | PledgeInstance<V>} Pledge
 */
/**
 * @template {any} Val
 * @template {any} [CancelReason=Error]
 */
export class PledgeInstance<Val extends unknown, CancelReason extends unknown = Error> {
    /**
     * @type {Val | CancelReason | null}
     */
    _v: Val | CancelReason | null;
    isResolved: boolean;
    /**
     * @type {Array<function(Val):void> | null}
     */
    _whenResolved: ((arg0: Val) => void)[] | null;
    /**
     * @type {Array<function(CancelReason):void> | null}
     */
    _whenCanceled: ((arg0: CancelReason) => void)[] | null;
    get isDone(): boolean;
    get isCanceled(): boolean;
    /**
     * @param {Val} v
     */
    resolve(v: Val): void;
    /**
     * @param {CancelReason} reason
     */
    cancel(reason: CancelReason): void;
    /**
     * @template R
     * @param {function(Val):Pledge<R>} f
     * @return {PledgeInstance<R>}
     */
    map<R>(f: (arg0: Val) => Pledge<R>): PledgeInstance<R, Error>;
    /**
     * @param {function(Val):void} f
     */
    whenResolved(f: (arg0: Val) => void): void;
    /**
     * @param {(reason: CancelReason) => void} f
     */
    whenCanceled(f: (reason: CancelReason) => void): void;
    /**
     * @return {Promise<Val>}
     */
    promise(): Promise<Val>;
}
export function create<T>(): PledgeInstance<T, Error>;
export function createWithDependencies<V, DEPS extends unknown[]>(init: (p: PledgeInstance<V, Error>, ...deps: Resolved<DEPS>) => void, ...deps: DEPS): PledgeInstance<V, Error>;
export function whenResolved<R>(p: Pledge<R>, f: (arg0: R) => void): void;
export function whenCanceled<P extends unknown>(p: P, f: P extends PledgeInstance<unknown, infer CancelReason extends unknown> ? (arg0: CancelReason) => void : (arg0: any) => void): void;
export function map<P, Q>(p: Pledge<P>, f: (r: P) => Q): Pledge<Q>;
export function all<PS extends PledgeMap>(ps: PS): PledgeInstance<Resolved<PS>, Error>;
export function coroutine<Result, YieldResults extends unknown>(f: () => Generator<Pledge<YieldResults> | PledgeInstance<YieldResults, any>, Result, any>): PledgeInstance<Result, Error>;
export function wait(timeout: number): PledgeInstance<undefined>;
export type Pledge<V> = V | PledgeInstance<V>;
export type PledgeMap = Array<Pledge<unknown>> | {
    [x: string]: Pledge<unknown>;
};
/**
 * <P>
 */
export type Resolved<P extends unknown> = P extends PledgeMap ? P extends infer T extends PledgeMap ? { [K in keyof T]: P[K] extends Pledge<infer V> ? V : P[K]; } : never : P extends Pledge<infer V_1> ? V_1 : never;
//# sourceMappingURL=pledge.d.ts.map
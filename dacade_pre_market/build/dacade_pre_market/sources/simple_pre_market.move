module dacade_pre_market::simple_pre_market {
    /*
    This is a simple pre market where users can freely buy and sell Coins without logging into the market, 
    Administrators can create markets and users can create orders and cancel orders.
    Users can also buy or sell Coins according to the description of the oder.
    */

    /* Dependencies */
    use sui::event::{Self};
    use sui::bag::{Self,Bag};
    use std::type_name::{Self,TypeName};
    use std::string::{Self,String};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};

    use dacade_pre_market::oracle::{Self, Price};

    /* Error Constants */
    const EMisMatchOwner: u64 = 0;

    /* Structs */
    // admin capability struct
    public struct AdminCap has key {
        id: UID
    }

    // Market struct
    public struct Market has key {
        id: UID,
        items: Bag,
    }

    //Buy order or Sell order struct 
    //"buy_or_sell" is a bool type, setting false for buy,true for sell 
    public struct Listing<phantom T> has key, store{
        id: UID,
        buy_or_sell: bool,
        amount: u64,
        balance: Balance<T>,
        for_object: String,
        price: u64,
        owner: address,
    }

    //Order listed 
    public struct Listed has copy, drop{
        buy_or_sell: bool,
        amount : u64,
        price: u64,
        for_object: String,
        collateral_type: TypeName,
        owner: address
    }
 
    /* Functions */
    fun init (ctx: &mut TxContext) {
       transfer::transfer(AdminCap{id: object::new(ctx)}, ctx.sender());
    }

    //only admin can create a market
    public entry fun create_market(_: &AdminCap, ctx: &mut TxContext) {
        let market = Market{
            id: object::new(ctx),
            items: bag::new(ctx),
        };
        transfer::share_object(market);
    }

    //User can create a Buy order or Sell order
    public entry fun create_order<T> (
        market: &mut Market,
        buy_or_sell: bool,
        amount : u64,
        collateral: Coin<T>,
        price: u64,
        for_object: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let id_ = object::new(ctx);
        let inner_ = object::uid_to_inner(&id_);
        let listing = Listing<T>{
            id: id_,
            buy_or_sell,
            amount,
            balance: coin::into_balance(collateral),
            for_object: string::utf8(for_object),
            price,
            owner: tx_context::sender(ctx),
        };
        bag::add(&mut market.items, inner_, listing);

        let listed = Listed{
            buy_or_sell,
            amount,   
            for_object: string::utf8(for_object),
            price,
            collateral_type: type_name::get<Coin<T>>(),
            owner: tx_context::sender(ctx),
        };
        event::emit<Listed>(listed);
    }

    //Order creator can cancel the order 
    public entry fun cancel_order<T> (
        market: &mut Market,
        item_id: ID,
        ctx: &mut TxContext,
    ) {
        let Listing {
            id,
            buy_or_sell:_,
            amount:_,
            balance: balance_,
            for_object:_,
            price:_,
            owner,
        } = bag::remove<ID, Listing<T>>(&mut market.items,item_id);
        assert!(owner == ctx.sender(), EMisMatchOwner);
        object::delete(id);
        let coin_ = coin::from_balance(balance_, ctx);
        transfer::public_transfer(coin_, ctx.sender());
    }

    //trade function 
    public fun trade<T>(
        market: &mut Market,
        price: Price,
        item_id: ID,
        coin: Coin<SUI>,
        ctx: &mut TxContext,
    ): Coin<T> {
        let Listing{
            id,
            buy_or_sell:_,
            amount:_,
            balance: mut balance_,
            for_object:_,
            price:_,
            owner,
        } = bag::remove<ID, Listing<T>>(&mut market.items,item_id);
        object::delete(id);
        // get the latest price from oracle 
        let (latest_result, scaling_factor, _) = oracle::destroy(price);
        // calculate the live sui price 
        let sui_amount = (((((coin::value(&coin) as u128) * latest_result / scaling_factor)) / 100) as u64);
        // calculate the stabil coin 
        let balance = balance::split(&mut balance_, sui_amount);
        // calculate the less coin 
        let user_coin = coin::from_balance(balance_, ctx);
        // transfer the coin from balance 
        transfer::public_transfer(user_coin, ctx.sender());
       // transfer the sui to owner
        transfer::public_transfer(coin, owner);
        // calculate the swap balance 
        let coin_ = coin::from_balance(balance, ctx);
        coin_
    }
}

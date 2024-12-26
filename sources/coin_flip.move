/*
    This quest is an implementation of the popular coin flip game. Users can participate in the game
    by predicting the outcome of 10 coin flips. If the user's prediction matches the actual outcome,
    they receive a prize. The flip outcome is provided by the module admin.

    Key concepts:
    - Resource accounts
    - AptosCoin
*/
module overmind::coin_flip {
    //==============================================================================================
    // Dependencies
    //==============================================================================================
    use std::signer;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use std::option::{Self, Option};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account::{Self, SignerCapability};
    #[test_only]
    use aptos_framework::aptos_coin;
    #[test_only]
    use aptos_framework::coin::BurnCapability;
    #[test_only]
    use aptos_framework::guid;

    //==============================================================================================
    // Constants - DO NOT MODIFY
    //==============================================================================================

    // Possible coin flips outcomes
    const HEAD: u8 = 0;
    const TAIL: u8 = 1;

    // the number of flips the user has to guess
    const NUMBER_OF_FLIPS: u64 = 10;
    
    // the amount of APT that the user receives if they predict the flips correctly
    const PRIZE_AMOUNT_APT: u64 = 1000000000; // 10 APT

    // seed for the module's resource account
    const SEED: vector<u8> = b"CoinFlip";

    //==============================================================================================
    // Error codes - DO NOT MODIFY
    //==============================================================================================

    const EInsufficientAptBalance: u64 = 0;
    const ESignerIsNotOvermind: u64 = 1;
    const EPrizeHasAlreadyBeenClaimed: u64 = 2;
    const EGameDoesNotExist: u64 = 3;
    const EInvalidNumberOfFlips: u64 = 4;
    const EInvalidFlipValue: u64 = 5;
    const EOvermindHasAlreadySubmittedTheFlips: u64 = 6;
    const EOvermindHasNotSubmittedTheFlipsYet: u64 = 7;

    //==============================================================================================
    // Module Structs - DO NOT MODIFY
    //==============================================================================================

    /*
        Resource struct holding data about the games, prize, and events
    */
    struct State has key {
        // ID of the next game - IDs start at 0
        next_game_id: u128,
        // SimpleMap instance mapping game IDs to Game instances
        games: SimpleMap<u128, Game>,
        // Boolean value indicating if any player has already claimed the prize
        prize_claimed: bool,
        // Resource account's SignerCapability
        cap: SignerCapability,
        // Events
        guess_flips_events: EventHandle<GuessFlipsEvent>,
        provide_flips_result_events: EventHandle<ProvideFlipsResultEvent>,
        claim_prize_events: EventHandle<ClaimPrizeEvent>,
    }

    /*
        Struct representing a single game
    */
    struct Game has store, drop, copy {
        // Address of a player participating in the game
        player_address: address,
        // Flips predicted by the player
        predicted_flips: vector<u8>,
        // Actual flips, that are provided by module admin
        flips_result: Option<vector<u8>>
    }

    //==============================================================================================
    // Event structs - DO NOT MODIFY
    //==============================================================================================

    /*
        Event to be emitted when a player submits their flip guesses
    */
    #[event]
    struct GuessFlipsEvent has store, drop {
        // ID of the game
        game_id: u128,
        // Flips predicted by the player
        flips: vector<u8>,
        // Timestamp when the event was created
        event_creation_timestamp_in_seconds: u64
    }

    /*
        Event to be emitted when the admin provides the flips result
    */
    #[event]
    struct ProvideFlipsResultEvent has store, drop {
        // ID of the game
        game_id: u128,
        // Flips provided by the admin
        flips_result: vector<u8>,
        // Timestamp when the event was created
        event_creation_timestamp_in_seconds: u64
    }

    /*
        Event to be emitted when the player's prediction is correct and they are rewarded with the 
            prize
    */
    #[event]
    struct ClaimPrizeEvent has store, drop {
        // ID of the game
        game_id: u128,
        // Address of the player, that predicted the flips correctly
        player_address: address,
        // Timestamp when the event was created
        event_creation_timestamp_in_seconds: u64
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

    /*
        Function called at the deployment time
        @param admin - signer representing the admin account
    */
    fun init_module(admin: &signer) {
        // TODO: Ensure the `admin` signer has enough APT coins for the prize.
        // 
        // HINT: 
        //      - Use the `PRIZE_AMOUNT_APT` constant as the amount of APT to check for
        //      - Use the `check_if_account_has_enough_apt_coins` function
        check_if_account_has_enough_apt_coins(signer::address_of(admin), PRIZE_AMOUNT_APT);
        // TODO: Create a resource account using the `admin` signer and the provided `SEED`
        //          constant
        let resource_acc:signer;
        let res_acc_caps:SignerCapability;
        (resource_acc, res_acc_caps) = account::create_resource_account(admin, SEED);
        // TODO: Register the resource account with AptosCoin and transfer `PRIZE_AMOUNT_APT` amount 
        //          of APT from the admin to the resource account
        coin::register<AptosCoin>(&resource_acc);
        coin::transfer<AptosCoin>(admin, signer::address_of(&resource_acc), PRIZE_AMOUNT_APT);
        // TODO: Create and move a State resource instance to the resource account
        let game_state = State {
                // ID of the next game - IDs start at 0
                next_game_id:0,
                // SimpleMap instance mapping game IDs to Game instances
                games:simple_map::create(),
                // Boolean value indicating if any player has already claimed the prize
                prize_claimed:false,
                // Resource account's SignerCapability
                cap:res_acc_caps,
                // Events
                guess_flips_events: account::new_event_handle<GuessFlipsEvent>(&resource_acc),
                provide_flips_result_events: account::new_event_handle<ProvideFlipsResultEvent>(&resource_acc),
                claim_prize_events: account::new_event_handle<ClaimPrizeEvent>(&resource_acc),
            };
        move_to(&resource_acc, game_state);
    }

    /*
        Creates a new Game instance for the player with their provide flip predictions and adds it
            to the State resource
        @param player - player participating in the game
        @flips - vector of the player's predicted flips (should consist only of `HEAD` and `TAIL` 
                    values)
    */
    public entry fun guess_flips(player: &signer, flips: vector<u8>) acquires State 
    {
        // TODO: Ensure that the prize has not be claimed yet
        //
        // HINT: Use the `check_if_prize_is_not_claimed_yet` function
        let state = borrow_global_mut<State>(get_resource_account_address());
        check_if_prize_is_not_claimed_yet(state);
        // TODO: Ensure the `flips` are valid
        //
        // HINT: Use the `check_if_flips_are_valid` function
        check_if_flips_are_valid(&flips);
        // TODO: Get the next game ID
        //
        // HINT: Use the `get_next_game_id` function
        let next_game_id = get_next_game_id(&mut state.next_game_id);
        // TODO: Create instance of Game and add it to State's `games` field
        let new_game = Game{
            // Address of a player participating in the game
            player_address: signer::address_of(player),
            // Flips predicted by the player
            predicted_flips: flips,
            // Actual flips, that are provided by module admin
            flips_result: option::none()
        };
        simple_map::add(&mut state.games, next_game_id, new_game);
        // TODO: Emit GuessFlipsEvent event
        let guess_flip_event = GuessFlipsEvent {
            // ID of the game
            game_id: next_game_id,
            // Flips predicted by the player
            flips: flips,
            // Timestamp when the event was created
            event_creation_timestamp_in_seconds: timestamp::now_microseconds()
        };
        event::emit_event<GuessFlipsEvent>(&mut state.guess_flips_events, guess_flip_event);
    }

    /*
        Allows the admin to provide flips that are checked against the player's flips, and transfers
        the prize to the player if their prediction matches the actual flips
        @param admin - signer representing the admin account
        @param game_id - ID of the game
        @param flips_result - vector of random flips (`HEAD` or `TAIL` values)
    */
    public entry fun provide_flip_results(
        admin: &signer, 
        game_id: u128, 
        flips_result: vector<u8>
    )  acquires State 
    {
        // TODO: Ensure the `admin` signer is the module deployer
        // 
        // HINT: Use the `check_if_signer_is_admin` function
        check_if_signer_is_admin(admin);

        // TODO: Ensure the prize has not been claimed yet
        //
        // HINT: Use the `check_if_prize_is_not_claimed_yet` function
        let state = borrow_global_mut<State>(get_resource_account_address());
        check_if_prize_is_not_claimed_yet(state);

        // TODO: Ensure the game with the provided ID exists
        // 
        // HINT: Use the `check_if_game_exists` function
        check_if_game_exists(&state.games, &game_id);

        // TODO: Ensure the `flips_result` is valid
        //
        // HINT: Use the `check_if_flips_are_valid` function
        check_if_flips_are_valid(&flips_result);
        // TODO: Ensure the admin has not already submitted the flip results for the game
        // 
        // HINT: Use the `check_if_overmind_has_not_submitted_the_flips_yet` function
        let the_game = simple_map::borrow_mut(&mut state.games, &game_id);
        check_if_overmind_has_not_submitted_the_flips_yet(the_game);

        // TODO: Fill Game's `flips_result` field with 'flips_result'
        option::fill<vector<u8>>(&mut the_game.flips_result, flips_result);
        // TODO: Emit ProvideFlipsResultEvent event
        let flips_result_event = ProvideFlipsResultEvent {
            // ID of the game
            game_id: game_id,
            // Flips provided by the admin
            flips_result: flips_result,
            // Timestamp when the event was created
            event_creation_timestamp_in_seconds:timestamp::now_microseconds()
        };
        event::emit_event<ProvideFlipsResultEvent>(&mut state.provide_flips_result_events, flips_result_event);
        // TODO: Check if `flips_result` matches the Game's `predicted_flips`
        // flis_result is what admin decides
        // the_game.predicted_flips is what user guesses
        let counter = 0;
        let result = true;
        while(counter < NUMBER_OF_FLIPS) {
            if(*vector::borrow(&flips_result, counter) == *vector::borrow(&the_game.predicted_flips, counter)) {
                counter = counter + 1;
                continue
            }
            else {
                result = false;
                break
            }
        };
        if (result) {
        // and if it does:
        //      1) Transfer `PRIZE_AMOUNT_APT` amount of APT from the resource account to the player 
        //          of the game
        //let resource_acc_address = account::get_signer_capability_address(&state.cap);
            coin::transfer<AptosCoin>(&account::create_signer_with_capability(&state.cap), the_game.player_address, PRIZE_AMOUNT_APT);
            //      2) Change State's `prize_claimed` to true
            state.prize_claimed = true;
            //      3) Emit ClaimPrizeEvent event
            let claim_prize_event = ClaimPrizeEvent {
                // ID of the game
                game_id: game_id,
                // Address of the player, that predicted the flips correctly
                player_address: the_game.player_address,
                // Timestamp when the event was created
                event_creation_timestamp_in_seconds: timestamp::now_microseconds()
            };
            event::emit_event<ClaimPrizeEvent>(&mut state.claim_prize_events, claim_prize_event);
        }
    }

    /*
        Gets and returns all games in a simple_map
        @returns - SimpleMap instance containing all games
    */
   #[view]
    public fun get_all_games(): SimpleMap<u128, Game> acquires State {
        // TODO: Return State's `games` field
        let state = borrow_global<State>(get_resource_account_address());
        return state.games
    }

    /*
        Returns result of comparing the player's predicted flips and the admin's flips result for 
            the provided game id
        @param game_id - ID of the game
        @returns - true if the flips matches, otherwise false
    */
    #[view]
    public fun get_game_result(game_id: u128): bool acquires State {
        // TODO: Ensure the game with the provided ID exists
        //
        // HINT: Use the `check_if_game_exists` function
        let state = borrow_global<State>(get_resource_account_address());
        check_if_game_exists(&state.games, &game_id);

        // TODO: Ensure the admin has already submitted the flip results for the game
        //
        // HINT: Use the `check_if_overmind_has_already_submitted_the_flips` function
        let the_game = simple_map::borrow(&state.games, &game_id);
        check_if_overmind_has_already_submitted_the_flips(the_game);
        // TODO: Compare the Game's `predicted_flips` and the Game's `flips_result` and return the 
        //          result
        let counter = 0;
        let result = true;
        while(counter < NUMBER_OF_FLIPS) {
            if(*vector::borrow(option::borrow<vector<u8>>(&the_game.flips_result), counter) == 
                    *vector::borrow(&the_game.predicted_flips, counter)) {
                counter = counter + 1;
                continue
            }
            else {
                result = false;
                break
            }
        };
        return result
    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================

    /*
        Creates the resource account address and returns it
        @returns - address of the resource account created in `init_module` function
    */
    inline fun get_resource_account_address(): address {
        // TODO: Get the return the address of the resource account created in `init_module` 
        //          function
        account::create_resource_address(&@overmind, SEED)
    }

    /*
        Takes the State's `next_game_id` field, increments it and returns the previous value
        @param next_game_id - `next_game_id` field of State resource
        @return - value before the increment
    */
    inline fun get_next_game_id(next_game_id: &mut u128): u128 {
        // TODO: Save current value of `next_game_id`
        let current_game_id:u128 = *next_game_id;

        // TODO: Increment `next_game_id`
        *next_game_id = *next_game_id + 1;
        // TODO: Return previously saved value
        current_game_id
    }

    //==============================================================================================
    // Validation functions
    //==============================================================================================

    inline fun check_if_account_has_enough_apt_coins(account: address, apt_amount: u64) {
        // TODO: Ensure that AptosCoin balance of `account` is equal or is greater than 
        //          `apt_amount`. If not, abort with code: `EInsufficientAptBalance`.
        let from_acc_balance:u64 = coin::balance<AptosCoin>(account);

        assert!(from_acc_balance >= apt_amount, EInsufficientAptBalance);
    }

    inline fun check_if_signer_is_admin(account: &signer) {
        // TODO: Ensure that address of `account` equals the `overmind` address stored in Move.toml 
        //          file. If not, abort with code: `ESignerIsNotOvermind`.
        assert!(signer::address_of(account) == @overmind, ESignerIsNotOvermind);

    }

    inline fun check_if_prize_is_not_claimed_yet(state: &State) {
        // TODO: Ensure that the State's `prize_claimed` field is false. If not, abort with code:
        //          `EPrizeHasAlreadyBeenClaimed`.
        assert!(state.prize_claimed == false, EPrizeHasAlreadyBeenClaimed);
    }

    inline fun check_if_game_exists(games: &SimpleMap<u128, Game>, game_id: &u128) {
        // TODO: Ensure that `games` simple_map contains the `game_id` key. If not, abort with code:
        //          `EGameDoesNotExist`.
        assert!(simple_map::contains_key(games, game_id) == true, EGameDoesNotExist);
    }

    inline fun check_if_flips_are_valid(flips: &vector<u8>) {
        // TODO: Ensure that length of `flips` equals `NUMBER_OF_FLIPS`. If not, abort with code:
        //          `EInvalidNumberOfFlips`.
        assert!(vector::length<u8>(flips) == NUMBER_OF_FLIPS, EInvalidNumberOfFlips);

        // TODO: Iterate over `flips` and ensure that each element equals either `HEAD` or `TAIL`.
        //      If an element is not either of those, abort with code: `EInvalidFlipValue`.
        let i = 0;
        while(i < NUMBER_OF_FLIPS) {
            let item = vector::borrow<u8>(flips, i);
            assert!(*item == HEAD || *item == TAIL, EInvalidFlipValue);
            i = i + 1;
        }

    }

    inline fun check_if_overmind_has_not_submitted_the_flips_yet(game: &Game) {
        // TODO: Ensure that the Game's `flips_result` field is none. If not, abort with code:
        //          `EOvermindHasAlreadySubmittedTheFlips`.
        assert!(option::is_none<vector<u8>>(&game.flips_result), EOvermindHasAlreadySubmittedTheFlips);
    }

    inline fun check_if_overmind_has_already_submitted_the_flips(game: &Game) {
        // TODO: Ensure the Game's `flips_result` field is some. If not, abort with code:
        //          `EOvermindHasNotSubmittedTheFlipsYet`.
        assert!(option::is_some<vector<u8>>(&game.flips_result), EOvermindHasNotSubmittedTheFlipsYet);
    }

    //==============================================================================================
    // Tests - DO NOT MODIFY
    //==============================================================================================

    #[test_only]
    inline fun claim_prize_unchecked(state: &mut State, burn_cap: &BurnCapability<AptosCoin>) {
        let resource_account_signer = account::create_signer_with_capability(&state.cap);
        let coins = coin::withdraw<AptosCoin>(&resource_account_signer, PRIZE_AMOUNT_APT);
        coin::burn(coins, burn_cap);
        state.prize_claimed = true;
    }

    #[test]
    fun test_init_module() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        let state = borrow_global<State>(resource_account_address);
        assert!(state.next_game_id == 0, 0);
        assert!(simple_map::length(&state.games) == 0, 1);
        assert!(!state.prize_claimed, 2);
        assert!(&state.cap == &account::create_test_signer_cap(resource_account_address), 3);
        assert!(event::counter(&state.guess_flips_events) == 0, 4);
        assert!(event::counter(&state.claim_prize_events) == 0, 5);
        assert!(event::counter(&state.provide_flips_result_events) == 0, 6);
        assert!(
            guid::creator_address(event::guid(&state.guess_flips_events)) == resource_account_address,
            7
        );
        assert!(
            guid::creator_address(event::guid(&state.claim_prize_events)) == resource_account_address,
            8
        );
        assert!(
            guid::creator_address(
                event::guid(&state.provide_flips_result_events)
            ) == resource_account_address,
            9
        );
        assert!(coin::balance<AptosCoin>(@overmind) == 0, 10);
        assert!(coin::balance<AptosCoin>(resource_account_address) == PRIZE_AMOUNT_APT, 11);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure(abort_code = 0, location = Self)]
    fun test_init_module_insufficient_apt_balance() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        init_module(&overmind);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_guess_flips() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 1, 1, 0];
        coin::register<AptosCoin>(&player);
        guess_flips(&player, flips);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        let state = borrow_global<State>(resource_account_address);
        assert!(state.next_game_id == 1, 0);
        assert!(simple_map::length(&state.games) == 1, 1);
        assert!(!state.prize_claimed, 2);
        assert!(&state.cap == &account::create_test_signer_cap(resource_account_address), 3);
        assert!(event::counter(&state.guess_flips_events) == 1, 4);
        assert!(event::counter(&state.claim_prize_events) == 0, 5);
        assert!(event::counter(&state.provide_flips_result_events) == 0, 6);
        assert!(
            guid::creator_address(event::guid(&state.guess_flips_events)) == resource_account_address,
            7
        );
        assert!(
            guid::creator_address(event::guid(&state.claim_prize_events)) == resource_account_address,
            8
        );
        assert!(
            guid::creator_address(
                event::guid(&state.provide_flips_result_events)
            ) == resource_account_address,
            9
        );
        assert!(coin::balance<AptosCoin>(@overmind) == 0, 10);
        assert!(coin::balance<AptosCoin>(resource_account_address) == PRIZE_AMOUNT_APT, 11);
        assert!(coin::balance<AptosCoin>(@0xACE) == 0, 12);

        let game = simple_map::borrow(&state.games, &0);
        assert!(game.player_address == @0xACE, 13);
        assert!(game.predicted_flips == flips, 14);
        assert!(option::is_none(&game.flips_result), 15);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)]
    fun test_guess_flips_prize_has_already_been_claimed() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        claim_prize_unchecked(borrow_global_mut<State>(resource_account_address), &burn_cap);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 1, 1, 0];
        guess_flips(&player, flips);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 4, location = Self)]
    fun test_guess_flips_invalid_number_of_flips() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1];
        guess_flips(&player, flips);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = Self)]
    fun test_guess_flips_invalid_flip_value() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 2, 0, 0, 1, 1, 0];
        guess_flips(&player, flips);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    fun test_provide_flip_results() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 1, 1, 0];
        coin::register<AptosCoin>(&player);
        guess_flips(&player, flips);

        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 0, 1, 1];
        provide_flip_results(&overmind, 0, flips_result);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        {
            let state = borrow_global<State>(resource_account_address);
            assert!(state.next_game_id == 1, 0);
            assert!(simple_map::length(&state.games) == 1, 1);
            assert!(!state.prize_claimed, 2);
            assert!(&state.cap == &account::create_test_signer_cap(resource_account_address), 3);
            assert!(event::counter(&state.guess_flips_events) == 1, 4);
            assert!(event::counter(&state.claim_prize_events) == 0, 5);
            assert!(event::counter(&state.provide_flips_result_events) == 1, 6);
            assert!(
                guid::creator_address(event::guid(&state.guess_flips_events)) == resource_account_address,
                7
            );
            assert!(
                guid::creator_address(event::guid(&state.claim_prize_events)) == resource_account_address,
                8
            );
            assert!(
                guid::creator_address(
                    event::guid(&state.provide_flips_result_events)
                ) == resource_account_address,
                9
            );
            assert!(coin::balance<AptosCoin>(@overmind) == 0, 10);
            assert!(coin::balance<AptosCoin>(resource_account_address) == PRIZE_AMOUNT_APT, 11);
            assert!(coin::balance<AptosCoin>(@0xACE) == 0, 12);

            let game = simple_map::borrow(&state.games, &0);
            assert!(game.player_address == @0xACE, 13);
            assert!(game.predicted_flips == flips, 14);
            assert!(*option::borrow(&game.flips_result) == flips_result, 15);
        };

        guess_flips(&player, flips);
        provide_flip_results(&overmind, 1, flips);

        let state = borrow_global<State>(resource_account_address);
        assert!(state.next_game_id == 2, 16);
        assert!(simple_map::length(&state.games) == 2, 17);
        assert!(state.prize_claimed, 18);
        assert!(&state.cap == &account::create_test_signer_cap(resource_account_address), 19);
        assert!(event::counter(&state.guess_flips_events) == 2, 20);
        assert!(event::counter(&state.claim_prize_events) == 1, 21);
        assert!(event::counter(&state.provide_flips_result_events) == 2, 22);
        assert!(
            guid::creator_address(event::guid(&state.guess_flips_events)) == resource_account_address,
            23
        );
        assert!(
            guid::creator_address(event::guid(&state.claim_prize_events)) == resource_account_address,
            24
        );
        assert!(
            guid::creator_address(
                event::guid(&state.provide_flips_result_events)
            ) == resource_account_address,
            25
        );
        assert!(coin::balance<AptosCoin>(@overmind) == 0, 26);
        assert!(coin::balance<AptosCoin>(resource_account_address) == 0, 27);
        assert!(coin::balance<AptosCoin>(@0xACE) == PRIZE_AMOUNT_APT, 28);

        let game = simple_map::borrow(&state.games, &1);
        assert!(game.player_address == @0xACE, 29);
        assert!(game.predicted_flips == flips, 30);
        assert!(*option::borrow(&game.flips_result) == flips, 31);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = Self)]
    fun test_provide_flip_results_signer_is_not_overmind() acquires State {
        let account = account::create_account_for_test(@0x58491651);
        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 0, 1, 1];
        provide_flip_results(&account, 0, flips_result);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = Self)]
    fun test_provide_flip_results_prize_has_already_been_claimed() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        claim_prize_unchecked(borrow_global_mut<State>(resource_account_address), &burn_cap);

        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 0, 1, 1];
        provide_flip_results(&overmind, 0, flips_result);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = Self)]
    fun test_provide_flip_results_game_does_not_exist() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 0, 1, 1];
        provide_flip_results(&overmind, 0, flips_result);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 4, location = Self)]
    fun test_provide_flip_results_invalid_numer_of_flips() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        guess_flips(&player, flips);

        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1];
        provide_flip_results(&overmind, 0, flips_result);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = Self)]
    fun test_provide_flip_results_invalid_flip_value() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        guess_flips(&player, flips);

        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 2, 1, 1];
        provide_flip_results(&overmind, 0, flips_result);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 6, location = Self)]
    fun test_provide_flip_results_overmind_has_already_submitted_the_flips() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        guess_flips(&player, flips);

        let flips_result = vector[0, 0, 1, 1, 0, 1, 0, 0, 1, 1];
        provide_flip_results(&overmind, 0, flips_result);
        provide_flip_results(&overmind, 0, flips_result);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    fun test_get_all_games() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        guess_flips(&player, flips);

        let player = account::create_account_for_test(@0xACED);
        let flips = vector[0, 0, 1, 0, 0, 1, 0, 0, 0, 0];
        guess_flips(&player, flips);

        let player = account::create_account_for_test(@0xDAD);
        let flips = vector[1, 1, 0, 1, 1, 0, 0, 0, 1, 0];
        guess_flips(&player, flips);

        let games = get_all_games();
        assert!(simple_map::length(&games) == 3, 0);
        assert!(simple_map::borrow(&games, &0) == &Game {
            player_address: @0xACE,
            flips_result: option::none(),
            predicted_flips: vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }, 1);
        assert!(simple_map::borrow(&games, &1) == &Game {
            player_address: @0xACED,
            flips_result: option::none(),
            predicted_flips: vector[0, 0, 1, 0, 0, 1, 0, 0, 0, 0]
        }, 2);
        assert!(simple_map::borrow(&games, &2) == &Game {
            player_address: @0xDAD,
            flips_result: option::none(),
            predicted_flips: vector[1, 1, 0, 1, 1, 0, 0, 0, 1, 0]
        }, 3);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    fun test_get_game_result() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        guess_flips(&player, flips);

        let flips_result = vector[1, 1, 1, 1, 1, 1, 1, 1, 1, 0];
        provide_flip_results(&overmind, 0, flips_result);

        assert!(!get_game_result(0), 0);

        let player = account::create_account_for_test(@0xACED);
        let flips = vector[0, 0, 1, 0, 0, 1, 0, 0, 0, 0];
        coin::register<AptosCoin>(&player);
        guess_flips(&player, flips);
        provide_flip_results(&overmind, 1, flips);

        assert!(get_game_result(1), 1);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = Self)]
    fun test_get_game_result_game_does_not_exist() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        get_game_result(0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    #[expected_failure(abort_code = 7, location = Self)]
    fun test_get_game_result_overmind_has_not_submitted_the_flips_yet() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let overmind = account::create_account_for_test(@overmind);
        coin::register<AptosCoin>(&overmind);
        aptos_coin::mint(&aptos_framework, @overmind, PRIZE_AMOUNT_APT);
        init_module(&overmind);

        let player = account::create_account_for_test(@0xACE);
        let flips = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        guess_flips(&player, flips);

        get_game_result(0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    fun test_get_resource_account_address() {
        let expected_resource_account = account::create_resource_address(&@overmind, SEED);
        assert!(expected_resource_account == get_resource_account_address(), 0);
    }

    #[test]
    fun test_get_next_game_id() {
        let next_game_id = 4654115;
        let current_game_id = get_next_game_id(&mut next_game_id);
        assert!(next_game_id == 4654116, 0);
        assert!(current_game_id == 4654115, 1);
    }
}
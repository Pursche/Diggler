module diggler.context;

import std.array;

import diggler.bot;

import irc.client;
import irc.tracker : IrcChannel, IrcTracker;

/**
 * _Context for operations used by command methods.
 *
 * $(DPREF command, CommandSet) subtypes an instance
 * of this type, allowing command methods to access
 * the properties and methods of this type without
 * any preceding qualification.
 *
 * Some operations are synchronous, non-blocking operations;
 * they may time a significant duration of time to complete,
 * but they do not block the thread from handling other events,
 * such as other command invocations.
 */
struct Context
{
	private:
	Bot _bot;
	Bot.ClientEventHandler client;
	IrcTracker tracker;
	string target;
	IrcUser _user;
	bool isPm;

	public:
	this(Bot _bot, Bot.ClientEventHandler client, IrcTracker tracker, string target, ref IrcUser _user, bool isPm)
	{
		this._bot = _bot;
		this.client = client;
		this.tracker = tracker;
		this.target = target;
		this._user = _user;
		this.isPm = isPm;
	}

	/**
	 * Create a new context from an existing one,
	 * but with a different originating channel/user.
	 *
	 * Params:
	 *    ctx = existing context to copy
	 *    target = channel name or user nickname
	 */
	this(Context ctx, string target)
	{
		import irc.protocol : channelPrefixes;
		this = ctx;

		this.target = target;

		switch(target.front)
		{
			foreach(channelPrefix; channelPrefixes)
			case channelPrefix:
				this.isPm = false;
				break;
			default:
				this.isPm = true;
		}
	}

	/// The current bot.
	Bot bot() @property pure nothrow
	{
		return _bot;
	}

	/// The _user that invoked the command.
	ref const(IrcUser) user() @property pure nothrow
	{
		return _user;
	}

	/**
	 * The _channel the command was invoked in.
	 *
	 * Throws an exception if the command originated from
	 * a private message.
	 */
	IrcChannel channel() @property
	{
		if(isPm)
			throw new Exception("not in a channel");

		return tracker[target];
	}

	/**
	 * Boolean whether or not the command was invoked
	 * from a private message.
	 */
	bool isPrivateMessage() @property pure nothrow
	{
		return isPm;
	}

	/**
	 * Reply to the channel in which the command was invoked.
	 * If there is more than one argument, the first argument
	 * is formatted with subsequent ones.
	 *
	 * If the command originated in a private message,
	 * the _reply is sent to the invoking user as a private message.
	 * See_Also:
	 *    $(STDREF format, formattedWrite)
	 */
	void reply(FmtArgs...)(in char[] fmt, FmtArgs fmtArgs)
	{
		client.sendf(target, fmt, fmtArgs);
	}

	/**
	 * Wait the given length of time before returning.
	 *
	 * This is a synchronous but non-blocking operation.
	 */
	void wait(double time)
	{
		auto curFiber = _bot.commandQueue.fiber();

		_bot.eventLoop.post(() {
			_bot.eventLoop.wakeFiber(curFiber);
		}, time);

		curFiber.yield();
	}

	/// Result of $(MREF Context.whois).
	static struct WhoisResult
	{
		/// Nickname, username and hostname of the _user.
		IrcUser user;

		/// Real name of the user.
		string realName;

		/// Channels the user is currently a member of.
		string[] channels;

		/// Boolean whether or not the user is an IRC
		/// (server or network-wide) _operator.
		bool operator = false;
	}

	/**
	 * Lookup more information about the user for the given nickname.
	 *
	 * This is a synchronous but non-blocking operation.
	 * Params:
	 *    nick = nickname of user to lookup
	 */
	WhoisResult whois(in char[] nick)
	{
		WhoisResult result;

		auto curFiber = _bot.commandQueue.fiber();

		void onWhoisReply(IrcUser user, in char[] realName)
		{
			if(user.nick == nick)
			{
				result.user = IrcUser(user.nick.idup, user.userName.idup, user.hostName.idup);
				result.realName = realName.idup;
				client.onWhoisReply.unsubscribeHandler(&onWhoisReply);
				_bot.eventLoop.wakeFiber(curFiber);
			}
		}

		client.onWhoisReply ~= &onWhoisReply;

		client.queryWhois(nick);

		curFiber.yield();

		return result;
	}

	version(none) bool isAdmin(in char[] nickName)
	{

	}

	/**
	 * Disconnect from the current network with the given message.
	 * Params:
	 *    msg = comment sent in _quit notification
	 */
	void quit(in char[] msg)
	{
		client.quit(msg);
	}
}

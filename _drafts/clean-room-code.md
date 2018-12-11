---
layout: post
title: Clean Room Code
date: 2018-11-20
type: post
excerpt: "Imagine if you never modified existing code but instead forked new versions..."
tags: ['coding','continuous-delivery']
---

## What is Clean Room Code?

Generally, a [clean room implementation](https://en.wikipedia.org/wiki/Clean_room_design) is a technique where a software engineer writes an implementation of a standard by intentionally not reading its existing implementation, usually a proprietary implementation. The aim is usually to avoid claims of copyright infringement.

Here is how I am using the term Clean Room Code:

> When adding new behavior to existing code, instead of editing the existing implementation, grow a whole new implementation by using the old implementation's test cases as a guide.

The new code will provide all the existing features of the existing implementation, and also the ones you are adding/changing, in a way that results in clearer, simpler code than if you tried to edit it in-place.

I settled on the name Clean Room Code because I often found myself reverse engineering desired behavior from unit tests, and so the parallel seemed helpful.

### Caveat About Naming

Clean Room Code is not the ideal name for this. Originally I saw someone on Twitter calling this same technique **Immutable Code** but trying to Google a technique of that name proved impossible since all the results were instead related to immutable data structures. If you have a better name, I’m happy to use it!

## Case Study: Sorting Customer Reviews

Let’s say you want to rank user reviews of products on your ecommerce app. You could start with an implementation that counts how many other users “Like” the review content, as a proxy for how useful others find the review. And to make it a little more advanced, you also use the reviewer’s follower count as a proxy for how influential they are.

```javascript
const scoreReview = (review) => review.likeCount + review.reviewer.followerCount;

const rankUserReviews = (reviews) => {
  const copy = [].concat(reviews);
  return copy.sort((a, b) => scoreReview(b) - scoreReview(a));
};

module.exports = {
  scoreReview,
  rankUserReviews
};
```
[View entire file on Github](https://github.com/vegetabill/clean-room-code-example/blob/master/index.js)

And a subset of its unit tests:

```javascript
describe("scoreReview", () => {
  it("should be higher when likeCount is higher", () => {
    const moreLikedReview = createReview({likeCount: 2});
    const lessLikedReview = createReview({likeCount: 1});
    assert(scoreReview(moreLikedReview) > scoreReview(lessLikedReview));
  });
});

describe("rankUserReviews", () => {
  it("should rank more likes higher", () => {
    const moreLikedReview = createReview({likeCount: 2});
    const lessLikedReview = createReview({ likeCount: 1 });
    const ranked = rankUserReviews([lessLikedReview, moreLikedReview]);
    assert.deepStrictEqual(ranked, [moreLikedReview, lessLikedReview]);
  });
});
```
[View entire file on Github](https://github.com/vegetabill/clean-room-code-example/blob/master/test/index_test.js)

So far so good. 

Now imagine this runs in production for awhile but then we notice a problem. Once a review achieves a bunch of Likes, it will just stay at the #1 spot forever since it is at the top of the pile and is therefore most likely to receive further Like’s (especially since we don’t have any downvoting).

The product team does some thinking and then decides we want to **give recent reviews a higher weight**, to allow new reviews to have a fair chance of getting some Like’s.

### Typical Edit-in-Place Solution

The usual approach here would be to add some new unit test cases and then add a logical branch to the code, maybe using an optional argument, such as in this example:

```javascript
const scoreReview = (review, opts = {}) => {
  const { useRecency = false } = opts;
  if (useRecency) {
    return review.likeCount + review.reviewer.followerCount - ageInWeeks(review);
  } else {
    return review.likeCount + review.reviewer.followerCount
  }
};

const rankUserReviews = (reviews, opts = {}) => {
  const { useRecency = false } = opts;
  const copy = [].concat(reviews);
  return copy.sort((a, b) => scoreReview(b, { useRecency }) - scoreReview(a, { useRecency }));
};
```
[View entire file on Github](https://github.com/vegetabill/clean-room-code-example/blob/typical-solution/index.js#L10)

Here we have added an optional arg to `rankUserReviews` and we use that inside the revised `scoreReview` function.

This works perfectly well, especially the first time you do it. But what if the original function looks more like this:

```javascript
const friendLikes = Liker.isFriend(review.likes).length;
  const nonFriendLikes = Liker.isNonFriend(review.likes).length;

  let score = (friendLikes * 0.75)
    + nonFriendLikes
    + review.reviewer.followerCount;
  
  if (InfluencerProgram.isParticipant(review.reviewer)) {
    score += 10;
  };
  
  if (review.reviewer.accountAge < 10) {
    score -= 5;
  }
  
  if (review.reviewer.friendCount < 10) {
    score += 5;
  }
  return score;
};
```
[View entire file on Github](https://github.com/vegetabill/clean-room-code-example/blob/more-realistic-starting-point/index.js#L8-L26)

Here we can see evidence of prior additions and experiments, some of which may no longer even be valid. In the usual way of writing code, *Edit-in-Place*, these special cases will stay forever unless you explicitly remove them. But what if we reverse that? Things only stay if you explicitly add them to the new *Clean Room Code implementation* (which I’ll refer to as v2).

### Clean Room Code Solution

Based on my earlier definition, if we can’t edit the existing method, or copy and paste it, we’re forced to create a new one that only includes the functionality we care about (up to and including all features provided by the existing method). By reimplement only what you are sure is relevant to your new use case, you will almost always end with simpler code.

#### Duplicate Unit Tests
Since we're following TDD, first we duplicate the original test cases to make sure we are still providing the existing behavior we care about. (Later, we'll discuss what to do with behavior we *don't* care about.)

```javascript
describe("scoreReviewWithRecency", () => {

  it("should be higher when likeCount is higher", () => {
    const moreLikedReview = createReview({likeCount: 2});
    const lessLikedReview = createReview({likeCount: 1});
    assert(scoreReviewWithRecency(moreLikedReview) > scoreReviewWithRecency(lessLikedReview));
  });
  // ...
}
```
[View entire file on Github](https://github.com/vegetabill/clean-room-code-example/blob/clean-room-recency/test/index_test.js#L34)

#### Implement New Function

Now that we have tests for a function, `rankUserReviewsWithRecency`, that doesn't yet exist, let's add it and make the tests pass:

```javascript
const scoreReview = (review) => review.likeCount + review.reviewer.followerCount;

const scoreReviewWithRecency = (review) => scoreReview(review) - ageInWeeks(review);

const rankUserReviews = (reviews) => {
  const copy = [].concat(reviews);
  return copy.sort((a, b) => scoreReview(b) - scoreReview(a));
};

const rankUserReviewsWithRecency = (reviews) => {
  const copy = [].concat(reviews);
  return copy.sort((a, b) => scoreReviewWithRecency(b) - scoreReviewWithRecency(a));
};
```
[View entire file on Github](https://github.com/vegetabill/clean-room-code-example/blob/clean-room-recency/index.js#L21-L24)

*Note the key difference, compared to Edit-in-Place, is with Clean Room Code you end up with two independent code paths.*

## Benefits
If you followed that example, you might be wondering why we would want to write code like this. At this moment, now we have duplicate code and tests. Hopefully I'll convince you why this is actually a preferable way to work.

### Less Scary Deployments
Assuming you're using Continuous Delivery on a system that must be highly-available, following Clean Room Code will make your life less stressful. In my experience, following this pattern allows you to spread out the risk of change across time into several production deploys.

The pattern looks something like this:

1. Create v2
1. Change **one and only one** existing caller of v1 to use v2 (ideally gated by a runtime toggle)
1. Deploy and monitor this. Detect issues early with less customer impact.
1. Once all issues fixed, migrate all callers of v1 to v2
1. Get rid of v1 and its tests

Even though the total aggregate risk is likely unchanged, it reduces the odds of a specific deploy causing a user-facing problem. For example, if your v2 function causes an accidental regression to one caller, this is clearly less impactful than simultaneously causing an issue for all callers, which can happen often with the Edit-in-Place technique. 

This is especially common when your new feature adversely interacts with production traffic patterns that were not anticipated during development of the original feature and thus did not end up as unit test cases. Your new implementation, Clean Room or otherwise, might not handle this input and result in user-facing errors.

Using Clean Room Code can limit the blast radius of this problem. I have found success calling both v2 and v1 in an important code path and the comparing the return value of each implementation, recording metrics for any discrepancies, while still returning the v1 result to callers:

```javascript
// super-important code path with dubious code coverage
function superImportantCode() {
  const v2 = v2Impl();
  const v1 = v1Impl();

  if (v2 !== v1) {
    Logger.debug(`superImportantCode.v2 mismatch: v1[${v1}] !== v2[${v2}]`);
  }

  return v1;
}
```

This technique can help you discover bugs in v2 (or even v1) and uncover what the test coverage is lacking so you can build confidence by adding them.

### Less Nesting

When you follow Edit-in-Place technique within existing code, you tend to expand the number of logical branches, if for no other reason than to support gradual canary release of the feature itself (but also often for the new code itself).

```javascript
if (Toggles.isNewFeatureEnabled()) {
  // do the new thing
} else {
  // do the old thing
}
```

This often occurs multiple times in the code path and requires more cognitive effort to “see” only the one active path. And you’re thoroughly testing all those branches, right?

By making the two branches into separate explicitly separate methods they end with a Flatter Shape (a crucial part of Sandi Metz’s [Squint Test](https://www.youtube.com/watch?v=8bZh5LMaSmE&t=5m12s)), which makes them easier to read, test, and modify.

### Clean Room is Cleaner

Last but certainly not least, by writing a brand new implementation, you’re presented with a blank slate.

* You might know a thing or two that the original author did not
  * This is true even if you are the author of the code since you likely learned some new techniques since originally writing v1
* You question the Why’s of each unit test case as you port each over to test v2
* Your fresh eyes may notice, in hindsight, that after additional use cases been overloaded into this method that perhaps an object-oriented solution would be a more elegant solution. This is sometimes harder to see when adding another logic branch.

Of course this is purely a psychological trick because of course nothing is stopping you from being equally suspicious of the existing code while following Edit-in-Place. But in practice a **Clean Room Code v2 always seems to end up leaner, simpler, and open for future changes in a way I rarely see with Edit-in-Place**. And this is why I keep returning to this technique.

I’m not 100% sure why this is, maybe it feels more like it’s “my responsibility” since my name will be on each and every blame line of v2 and I want future people to nod along appreciatively at my choices if possible, instead of grumbling at why I took a shortcut and just left it all as-is after satisfying my immediate need from the current feature I was adding.

I find this technique especially beneficial in a big legacy codebase full of vestigial branches that are actually dead. Those never make it to v2 and the code is leaner as a result. Doing this repeatedly turns commonly-modified areas into areas that are productive to modify, rather than inspiring dread and yielding slow results and higher risk of introducing bugs.

## Downsides
Before you would consider giving this technique a try, it’s only fair to discuss the costs to the Clean Room Code technique as well.

### Violating DRY
You’re flagrantly violating Don’t Repeat Yourself (DRY). There will definitely be duplicate code and duplicate tests, at least for awhile. As mentioned, you definitely want to document and leave cross-linkings in comments. If you aren’t conscientious, you can do more harm than good with Clean Room Code, particularly if you are the only developer on your team practicing it. “Oh great, here’s another one of those v2 methods Bill forgot to clean up…”

Don’t do it carelessly! Always take the extra time to move to a stable stopping point that you’d be happy existing for a very long time, and document clearly in the comments what blockers remain and what the next steps should be if those blockers can be resolved.

### Overkill
By definition, you’re adding more moving parts, more pull requests with bigger diffs, more live code paths (at least temporarily), and more production releases that stretch out the calendar time before the new feature is in user's hands. Obviously for something urgent with a tight timeframe, Edit-in-Place would be much preferred.

And obviously this will not change the risk in a meaningful way if your method is used in several places, but one caller is vastly more important than all the others, such as a call from your app’s landing page that can cause a bad outage if there is a problem with v2. (Although you could mitigate this runtime toggles that let you send only a percentage of requests to v2).

You’ll have to develop your own heuristics to know when it’s worth employing the Clean Room Code technique, but I will say **I have underused this technique more than I have overused it**, meaning there were some fairly large code changes I undertook where, in retrospect, I felt that applying the technique would have prevented issues but I did not choose it at the start since it seemed like the overhead was too high.

Practice will help here. After replacing three legacy procedural implementations with clean and simple object-oriented solutions in the past few months, I now have the confidence to know where this technique will help and have been using it much more often.


## Stopping Points
Ideally, you can always replace v1 with v2 and leave no trace of its existence. But this isn't always possible. When we can't completely drop v1, this presents a problem. Obviously we don’t want to just keep doubling the number of methods, which would introducing maintenance headaches. Here are the two situations I find myself in when applying this pattern and how I make sure I'm at a stable stopping point.

### Case 1: New v2 Method is Temporary and Quickly and Completely Replaces Old
 I often explicitly name the new method with a ‘v2’ suffix as visual reminder that it’s aim is to be newer and preferred to previous versions. If it’s possible for you to safely consolidate all existing code to use the new version, over a number of controlled refactorings, that should always be your goal. For 90% of cases, this is what I do, and it usually just takes a few pull requests as you absorb more and more of existing use cases with v2. Then you can drop the v1, rename v2 so it has no version number at all and carry on.

### Case 2: Old v1 Method is Needed for Limited Cases
Sometimes it’s not possible to totally remove v1, especially when it is used in high-impact code paths where unit test coverage doesn’t appear strong and/or the business context and ownership is unclear. Perhaps you’ve reached the point of diminishing returns: 80% of the important code is using v2 and the remaining 20% would be time-consuming and dangerous to migrate.

Just because a handful legacy use case still use the old implementation doesn’t mean that moving the other uses to v2 is not a demonstrable improvement. For example, if v2 is an open-closed object-oriented solution, it will be able to accommodate new requirements very cheaply and v1 can continue to serve the old use cases.

In addition, all the extra work you did to follow Clean Room Code makes previous organization unknowns explicit that others can leverage in the future:
* “Hmm I can see that in 2017 Sally was unable to prove that this code path was unused, so if nothing has changed since then except the knowledge has rotted further, I’m not going to try to find out and just let sleeping dogs lie and leave in this possibly unused code.” 
* Or perhaps if you’re a more typical software engineer: “Bill tried to get to the bottom of this but didn’t, but where he failed, I will succeed, but can at least use his notes and comments as a starting point for where to probe for misses”

In these cases, after migrating the usages I can do safely, I often rename the old method with a deprecated in the name somewhere (or if you’re in a language like Java, add the official @Deprecated annotation so it will have a strikethrough font in most IDEs, at least subtly making engineers feel bad if they call it from new code). 

As mentioned before, in both v1 and v2 method doc comments, you should describe which version to use in what circumstances.

## Summarizing Clean Room Code
If you’ve supported a long-lived API, I’m sure you have noticed direct parallels between the Clean Room Code technique with versioning APIs. If you haven’t done it before, versioning an API is a technique where clients can gradually opt-in to new endpoints that have different features and schemas, often by including an additional segment in the URL, i.e. `https://your.api.com/v2/products/ABC.json`. If a new capability is needed that can’t be backwards compatible with v1 requests, a v2 version of the API is created. Clients can be extended to use v2. Once no more clients are using v1, or some reasonable support deadline has passed, v1 can be removed entirely.

I hope I’ve given you some food for thought for the next time you approach a medium or large architecture change in your codebase. If you’re interested, give this technique a try and see how it affects the end result, the risk of the changes, and the eventual state of the code. I think you’ll be happy to have another tool in your repertoire for dealing with your codebase.

*Special thanks for fellow Goodreaders, Aditi Sharma and William Cline, for feedback on drafts of this blog and for putting up with all my Clean Room Code pull requests.*












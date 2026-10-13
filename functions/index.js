import { onRequest, onCall } from "firebase-functions/v2/https";
import { onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import admin from "firebase-admin"; 
import { searchPropertiesFlow } from "./genkit.js";
import axios from "axios";

if (!admin.apps.length) {
	admin.initializeApp();
}


export const paymongoWebhook = onRequest(
	{ region: "us-central1", secrets: ["PAYMONGO_SECRET_KEY"] },
	async (req, res) => {
		try {
			const event = req.body;
			logger.info("Incoming webhook:", JSON.stringify(event, null, 2));

			const type = event?.data?.attributes?.type;
			const objectData = event?.data?.attributes?.data || {};
			let checkoutId = null;

			if (type?.startsWith("checkout_session")) {
				checkoutId = objectData?.id || event?.data?.id;
			} else if (type?.startsWith("payment")) {
				checkoutId = objectData?.attributes?.checkout_session_id || null;
			}

			if (!checkoutId) {
				logger.error("Could not resolve checkout_session_id", { type });
				return res.status(200).send({ ignored: true });
			}

			const txRef = db.collection("transactions").doc(checkoutId);
			const txSnap = await txRef.get();

			if (!txSnap.exists) {
				await txRef.set({
					transactionId: checkoutId,
					status: "pending",
					createdAt: admin.firestore.FieldValue.serverTimestamp(),
					updatedAt: admin.firestore.FieldValue.serverTimestamp(),
					source: "webhook",
				});
				logger.info(`Created Firestore doc for ${checkoutId}`);
			}

			let newStatus = null;
			switch (type) {
				case "checkout_session.payment.paid":
				case "payment.paid":
				case "checkout_session.paid":
					newStatus = "succeeded";
					break;
				case "payment.failed":
				case "payment.expired":
				case "checkout_session.payment_failed":
				case "checkout_session.expired":
					newStatus = "failed";
					break;
				case "payment.processing":
					newStatus = "processing";
					break;
				default:
					logger.info(`Unhandled webhook type: ${type}`);
			}

			if (newStatus) {
				const method =
					objectData?.attributes?.payment_method_used ||
					objectData?.attributes?.payments?.[0]?.attributes?.source?.type ||
					null;

				await txRef.update({
					status: newStatus,
					updatedAt: admin.firestore.FieldValue.serverTimestamp(),
					...(method ? { method } : {}),
					...(newStatus === "succeeded"
						? { paidAt: admin.firestore.FieldValue.serverTimestamp() }
						: {}),
				});

				logger.info(
					`Updated ${checkoutId} -> ${newStatus} ${
						method ? `(${method})` : ""
					}`
				);

				if (newStatus === "succeeded") {
					const latestTx = (await txRef.get()).data();
					const { 
						ownerId, 
						amount = 0, 
						rumeServiceFee = 0,
						paymongoFee = 0,
						payerName, 
						bookingId,
						userId,
						paymentType = "rent" 
					} = latestTx || {};
					
				
					if (bookingId && paymentType === "booking") {
						try {
							await db.collection("bookings").doc(bookingId).update({
								status: "booked",
								transactionId: checkoutId,
								paidAt: admin.firestore.FieldValue.serverTimestamp(),
								updatedAt: admin.firestore.FieldValue.serverTimestamp(),
							});
							logger.info(`Booking ${bookingId} marked as 'booked'`);
							
							
							const bookingStatsSnap = await db.collection("bookings").doc(bookingId).get();
							if (bookingStatsSnap.exists) {
								const bookingData = bookingStatsSnap.data();
								const propertyId = bookingData.propertyId;
								
								if (propertyId) {
									const monthKey = new Date().toISOString().substring(0, 7);
									await db.collection('properties')
										.doc(propertyId)
										.collection('bookingStats')
										.doc(monthKey)
										.set({
											booked: admin.firestore.FieldValue.increment(1),
											month: monthKey
										}, { merge: true });
									
									logger.info(`Incremented booked stats for property ${propertyId}`);
								}
							}

							
							const bookingSnap = await db.collection("bookings").doc(bookingId).get();
							if (bookingSnap.exists && ownerId) {
								const bookingData = bookingSnap.data();
								const ownerDoc = await db.collection("users").doc(ownerId).get();

								if (ownerDoc.exists) {
									const ownerFcmToken = ownerDoc.data()?.fcmToken;
									if (ownerFcmToken) {
										const notificationAmount = (latestTx.totalAmount / 100).toFixed(2);
										const message = {
											notification: {
												title: "Payment Received!",
												body: `${payerName} has paid ₱${notificationAmount} for ${bookingData.roomName} at ${bookingData.propertyName}. The room is now booked.`,
											},
											token: ownerFcmToken,
											
											android: {
												priority: "high",
												notification: {
													icon: "launcher_icon.png", 
													color: "#1565C0", 
												},
											},
											apns: {
												payload: {
													aps: { sound: "default" },
												},
											},
										};

										try {
											await admin.messaging().send(message);
											logger.info(`Successfully sent payment notification to owner ${ownerId}`);
										} catch (messagingError) {
											logger.error(`Failed to send payment notification to owner ${ownerId}:`, messagingError);
										}

										
										await db.collection("users").doc(ownerId).collection("notifications").add({
											title: "Payment Received!",
											body: `${payerName} has paid ₱${notificationAmount} for ${bookingData.roomName}. The room is now booked.`,
											createdAt: admin.firestore.FieldValue.serverTimestamp(),
											read: false,
											type: "payment_received",
											relatedId: bookingId,
										});
									} else {
										logger.warn(`FCM token not found for owner ${ownerId}. Cannot send payment notification.`);
									}
								} else {
									logger.error(`Owner user document ${ownerId} not found.`);
								}
							} else {
								logger.warn(`Booking ${bookingId} or ownerId not found for sending notification.`);
							}
						} catch (err) {
							logger.error(`Failed to update booking ${bookingId}:`, err);
						}
					}

					if (bookingId && paymentType === "final_payment") {
						try {
							await db.collection("bookings").doc(bookingId).update({
								leavePaymentStatus: "fully_paid",
								updatedAt: admin.firestore.FieldValue.serverTimestamp(),
							});
							logger.info(`Booking ${bookingId} marked with leavePaymentStatus 'fully_paid'.`);
						} catch (err) {
							logger.error(`Failed to update booking ${bookingId} for final_payment:`, err);
						}

					}

					
					if (ownerId) {
						
						const walletRef = db.collection("wallets").doc(ownerId);
						const netAmount = amount; 

						await db.runTransaction(async (t) => {
							const walletSnap = await t.get(walletRef);
							if (!walletSnap.exists) {
								t.set(walletRef, {
									userId: ownerId,
									amount: netAmount,
									createdAt: admin.firestore.FieldValue.serverTimestamp(),
									updatedAt: admin.firestore.FieldValue.serverTimestamp(),
								});
							} else {
								t.update(walletRef, {
									amount: admin.firestore.FieldValue.increment(netAmount),
									updatedAt: admin.firestore.FieldValue.serverTimestamp(),
								});
							}

							t.set(walletRef.collection("transactions").doc(checkoutId), {
								transactionId: checkoutId,
								amount,
								commission: rumeServiceFee,
								paymongoFee: paymongoFee,
								netAmount: netAmount, 
								payerName: payerName || "Unknown",
								paymentType,
								propertyId: latestTx?.propertyId || null,
								roomId: latestTx?.roomId || null, 
								userId: userId || null, 
								method: latestTx?.method || null, 
								ownerId: ownerId || null, 
								bookingId: bookingId || null, 
								status: newStatus,
								createdAt:
									latestTx?.createdAt ||
									admin.firestore.FieldValue.serverTimestamp(),
							});
						});

						logger.info(
							`Wallet for owner ${ownerId} credited with ₱${(netAmount / 100).toFixed(2)} for ${paymentType} payment.`
						);
					}

					
					if (rumeServiceFee > 0) {
						const adminWalletRef = db.collection("wallets").doc(RUME_ADMIN_UID);

						await db.runTransaction(async (t) => {
							const adminWalletSnap = await t.get(adminWalletRef);
							if (!adminWalletSnap.exists) {
								t.set(adminWalletRef, {
									userId: RUME_ADMIN_UID,
									amount: rumeServiceFee,
									role: "admin",
									createdAt: admin.firestore.FieldValue.serverTimestamp(),
									updatedAt: admin.firestore.FieldValue.serverTimestamp(),
								});
							} else {
								t.update(adminWalletRef, {
									amount: admin.firestore.FieldValue.increment(rumeServiceFee),
									updatedAt: admin.firestore.FieldValue.serverTimestamp(),
								});
							}

							
							t.set(adminWalletRef.collection("transactions").doc(checkoutId), {
								transactionId: checkoutId,
								amount: rumeServiceFee, 
								paymentType: "commission", 
								originalPayerId: userId,
								originalPayerName: payerName,
								originalBookingId: bookingId,
								originalPropertyId: latestTx?.propertyId || null,
								status: newStatus,
								createdAt:
									latestTx?.createdAt ||
									admin.firestore.FieldValue.serverTimestamp(),
							});
						});
						logger.info(
							`RuMe admin wallet credited with ₱${(rumeServiceFee / 100).toFixed(2)} commission.`
						);
					}
				}
			}

			return res.status(200).send({ received: true });
		} catch (err) {
			logger.error("Webhook error:", err.response?.data || err.message || err);
			return res.status(500).send("Webhook handler error");
		}
	}
);

export const createPaymongoCheckoutSession = onRequest(
	{ region: "us-central1", secrets: ["PAYMONGO_SECRET_KEY"] },
	async (req, res) => {
		try {
			const {
				email,
				payerName,
				userId,
				totalAmount, 
				paymongoFee,
				rumeServiceFee, 
				description,
				propertyId,
				bookingId,
				roomId,
				ownerId, 
				paymentType = "rent"
			} = req.body;

			if (!email || !userId || !payerName || !totalAmount || !ownerId || paymongoFee === undefined || rumeServiceFee === undefined) {
				return res.status(400).send("Missing required fields.");
			}


			const amount = totalAmount - rumeServiceFee - paymongoFee;
			const commission = rumeServiceFee; 

			const redirectPageUrl = "https://rume-612e1.web.app/redirect.html";

			const response = await axios.post(
				"https://api.paymongo.com/v1/checkout_sessions",
				{
					data: {
						attributes: {
							billing: { email },
							description,
							success_url: `${redirectPageUrl}?checkout_id={CHECKOUT_ID}`,
							cancel_url: `${redirectPageUrl}?checkout_id={CHECKOUT_ID}`,
							payment_method_types: ["gcash", "paymaya","grab_pay","qrph"],
							line_items: [
								{
									name: description,
									amount: totalAmount,
									currency: "PHP",
									quantity: 1,
								},
							],
						},
					},
				},
				{
					headers: {
						"Content-Type": "application/json",
						Authorization: `Basic ${Buffer.from(
							`${process.env.PAYMONGO_SECRET_KEY}:`
						).toString("base64")}`,
					},
				}
			);

			const checkout = response.data.data;
			const checkoutId = checkout.id;

			const now = admin.firestore.FieldValue.serverTimestamp();
			await db.collection("transactions").doc(checkoutId).set({
				transactionId: checkoutId,
				userId,
				ownerId,
				email,
				payerName,
				role: "seeker",
				propertyId: propertyId || null,
				bookingId: bookingId || null,
				roomId: roomId || null,
				amount,
				commission: rumeServiceFee, 
				rumeServiceFee, 
				paymongoFee,
				totalAmount,
				currency: "PHP",
				description,
				paymentType,
				method: null,
				status: "pending",
				createdAt: now,
				source: "checkout_session",
			});

			return res.status(200).send({
				checkoutUrl: checkout.attributes.checkout_url,
			});
		} catch (err) {
			logger.error("PayMongo error", err.response?.data || err.message);
			return res.status(500).send("Failed to create checkout session.");
		}
	}
);



export const onBookingStatusUpdate = onDocumentUpdated(
	{ document: "bookings/{bookingId}", region: "us-central1" },
	async (event) => {
		const bookingId = event.params.bookingId;
		const beforeData = event.data.before.data();
		const afterData = event.data.after.data();

	
		if (beforeData.status !== "booked" && afterData.status === "booked") {
			const { propertyId, roomId, seekerId } = afterData;

			if (!propertyId || !roomId || !seekerId) {
				logger.error("Missing required fields in booking", { bookingId });
				return;
			}

			try {
				const monthKey = new Date().toISOString().substring(0, 7);
				await db.collection('properties')
					.doc(propertyId)
					.collection('bookingStats')
					.doc(monthKey)
					.set({
						booked: admin.firestore.FieldValue.increment(1),
						month: monthKey
					}, { merge: true });
				
				logger.info(`✅ Incremented booked stats for property ${propertyId}`);
			} catch (statsError) {
				logger.error("Error incrementing booked stats:", statsError);
			}

			try {
				const batch = db.batch();

				
				const roomRef = db
					.collection("properties")
					.doc(propertyId)
					.collection("rooms")
					.doc(roomId);

				batch.update(roomRef, {
					status: "occupied",
					occupiedBy: seekerId,
					occupiedAt: admin.firestore.FieldValue.serverTimestamp(),
					updatedAt: admin.firestore.FieldValue.serverTimestamp(),
				});

				
				const allSeekerBookingsSnapshot = await db
					.collection("bookings")
					.where("seekerId", "==", seekerId)
					.where("status", "in", ["pending", "awaiting_payment"])
					.get();

				allSeekerBookingsSnapshot.docs.forEach((doc) => {
					if (doc.id !== bookingId) {
						batch.delete(doc.ref);
					}
				});

				
				const otherRoomBookingsSnapshot = await db
					.collection("bookings")
					.where("roomId", "==", roomId)
					.where("status", "in", ["pending", "awaiting_payment"])
					.get();

				otherRoomBookingsSnapshot.docs.forEach((doc) => {
					if (doc.id !== bookingId) {
						batch.delete(doc.ref);
					}
				});

				await batch.commit();

				logger.info(
					`Room ${roomId} marked as occupied. Seeker ${seekerId} confirmed. Deleted ${
						allSeekerBookingsSnapshot.size + otherRoomBookingsSnapshot.size
					} other bookings.`
				);
			} catch (error) {
				logger.error("Error updating room status:", error);
			}
		}

	
		if (
			beforeData.status === "pending" &&
			afterData.status === "awaiting_payment"
		) {
			const { seekerId, propertyName, roomName } = afterData;

			if (!seekerId) {
				logger.error("No seekerId found in booking, cannot send notification.", {
					bookingId,
				});
				return;
			}

			try {
				
				const userDoc = await db.collection("users").doc(seekerId).get();
				if (!userDoc.exists) {
					logger.error(`Seeker user document ${seekerId} not found.`);
					return;
				}

				const fcmToken = userDoc.data()?.fcmToken;
				if (!fcmToken) {
					logger.warn(`FCM token not found for seeker ${seekerId}.`);
					return;
				}

				
				const message = {
					notification: {
						title: "Booking Approved! 🎉",
						body: `Your booking for ${roomName} at ${propertyName} is approved. Proceed to payment to secure your room!`,
					},
					token: fcmToken,
					
					android: {
						priority: "high",
						notification: {
							icon: "launcher_icon.png",
							color: "#1565C0",
						},
					},
					apns: {
						payload: {
							aps: {
								sound: "default",
							},
						},
					},
				};

				await admin.messaging().send(message);
				logger.info(`Successfully sent 'awaiting_payment' notification to seeker ${seekerId}`);

			
				await db.collection("users").doc(seekerId).collection("notifications").add({
					title: "Booking Approved! 🎉",
					body: `Your booking for ${roomName} at ${propertyName} is approved. Proceed to payment to secure your room!`,
					createdAt: admin.firestore.FieldValue.serverTimestamp(),
					read: false,
					type: "booking_approved",
					relatedId: bookingId,
				});
			} catch (error) {
				logger.error(`Error sending notification to seeker ${seekerId}:`, error);
			}

			
			const { ownerId, seekerName } = afterData;
			if (!ownerId) {
				logger.error("No ownerId found in booking, cannot send notification.", {
					bookingId,
				});
				return; 
			}

			try {
				
				const ownerUserDoc = await db.collection("users").doc(ownerId).get();
				if (!ownerUserDoc.exists) {
					logger.error(`Owner user document ${ownerId} not found.`);
					return;
				}

				const ownerFcmToken = ownerUserDoc.data()?.fcmToken;
				if (!ownerFcmToken) {
					logger.warn(`FCM token not found for owner ${ownerId}.`);
					return;
				}

				
				const ownerMessage = {
					notification: {
						title: "Booking Approved",
						body: `You have approved the booking for ${seekerName}. Waiting for their payment to confirm.`,
					},
					token: ownerFcmToken,
					
					android: {
						priority: "high",
						notification: {
							icon: "launcher_icon.png",
							color: "#1565C0",
						},
					},
					apns: {
						payload: {
							aps: { sound: "default" },
						},
					},
				};
				await admin.messaging().send(ownerMessage);
				logger.info(`Successfully sent 'booking approved' confirmation to owner ${ownerId}`);

				
				await db.collection("users").doc(ownerId).collection("notifications").add({
					title: "Booking Approved",
					body: `You have approved the booking for ${seekerName}. Waiting for their payment to confirm.`,
					createdAt: admin.firestore.FieldValue.serverTimestamp(),
					read: false,
					type: "booking_action_confirm",
					relatedId: bookingId,
				});
			} catch (error) {
				logger.error(`Error sending confirmation notification to owner ${ownerId}:`, error);
			}

			
				try {
				const otherPendingBookings = await db
					.collection("bookings")
					.where("seekerId", "==", seekerId)
					.where("status", "==", "pending")
					.get();

				if (!otherPendingBookings.empty) {
					const batch = db.batch();
					let deletedCount = 0;
					otherPendingBookings.forEach((doc) => {
						if (doc.id !== bookingId) {
							batch.delete(doc.ref);
							deletedCount++;
						}
					});
					await batch.commit();
					logger.info(`Deleted ${deletedCount} other pending bookings for seeker ${seekerId}`);
				}
			} catch (error) {
				logger.error("Error deleting other pending bookings:", error);
			}
		}
	}
);

export const onFeedbackWrite = onDocumentWritten(
	{ document: "feedbacks/{feedbackId}", region: "us-central1" },
	async (event) => {
		const beforeData = event.data.before.data();
		const afterData = event.data.after.data();

		
		const isNewlyApproved = beforeData?.status !== "approved" && afterData?.status === "approved";
		const wasApprovedAndDeleted = beforeData?.status === "approved" && !afterData;
		const isNewAndApproved = !beforeData && afterData?.status === "approved";

		if (!isNewlyApproved && !wasApprovedAndDeleted && !isNewAndApproved) {
			logger.info(
				"Feedback write did not involve an 'approved' status change. Skipping rating update.",
				{ before: beforeData?.status, after: afterData?.status }
			);
			return;
		}

		
		const propertyId = afterData?.propertyId || beforeData?.propertyId;

		if (!propertyId) {
			logger.info("No propertyId found in feedback document. Skipping rating update.");
			return;
		}

		try {
			const propertyRef = db.collection("properties").doc(propertyId);

			
			const feedbacksSnapshot = await db.collection("feedbacks")
				.where("propertyId", "==", propertyId)
				.where("status", "==", "approved")
				.get();

			let totalRating = 0;
			const ratingCount = feedbacksSnapshot.size;

			if (ratingCount > 0) {
				feedbacksSnapshot.forEach((doc) => {
					const rating = doc.data().rating || 0;
					totalRating += rating;
				});

				const averageRating = totalRating / ratingCount;

				
				await propertyRef.update({
					averageRating: averageRating,
					ratingCount: ratingCount,
				});

				logger.info(`Updated ratings for property ${propertyId}: Avg Rating: ${averageRating.toFixed(2)}, Count: ${ratingCount}`);
			} else {
				
				await propertyRef.update({
					averageRating: 0,
					ratingCount: 0,
				});
				logger.info(`Reset ratings for property ${propertyId} as no approved feedback was found.`);
			}
		} catch (error) {
			logger.error(`Error updating ratings for property ${propertyId}:`, error);
		}
	});

export const cleanupStaleBookings = onSchedule(
	{
		schedule: "every 6 hours",
		region: "us-central1",
		timeZone: "Asia/Manila",
	},
	async (event) => {
		const oneDayAgo = admin.firestore.Timestamp.fromDate(
			new Date(Date.now() - 24 * 60 * 60 * 1000)
		);

		try {
			const staleBookingsSnapshot = await db
				.collection("bookings")
				.where("status", "==", "awaiting_payment")
				.where("updatedAt", "<", oneDayAgo)
				.get();

			if (staleBookingsSnapshot.empty) {
				logger.info("No stale bookings found");
				return;
			}

			const batch = db.batch();

			staleBookingsSnapshot.docs.forEach((doc) => {
				batch.delete(doc.ref);
			});

			await batch.commit();

			logger.info(
				`Deleted ${staleBookingsSnapshot.size} stale bookings (>24h awaiting payment)`
			);
		} catch (error) {
			logger.error("Error cleaning up stale bookings:", error);
		}
	}
);

export const sendMonthlyRentReminders = onSchedule(
	{
		schedule: "0 9 1 * *",
		timeZone: "Asia/Manila",
		region: "us-central1",
	},
	async (event) => {
		logger.info("Starting monthly rent reminder job...");

		try {
			
			const activeBookingsSnapshot = await db
				.collection("bookings")
				.where("status", "==", "booked")
				.get();

			if (activeBookingsSnapshot.empty) {
				logger.info("No active bookings found. Exiting job.");
				return;
			}

			const now = new Date();
			const currentMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
			const nextMonthStart = new Date(now.getFullYear(), now.getMonth() + 1, 1);

			let remindersSent = 0;

			
			for (const bookingDoc of activeBookingsSnapshot.docs) {
				const bookingData = bookingDoc.data();
				const { seekerId, propertyId, propertyName, roomName } = bookingData;

				if (!seekerId || !propertyId) {
					logger.warn(`Skipping booking ${bookingDoc.id} due to missing seekerId or propertyId.`);
					continue;
				}

			
				const rentPaidSnapshot = await db
					.collection("transactions")
					.where("userId", "==", seekerId)
					.where("propertyId", "==", propertyId)
					.where("status", "==", "succeeded")
					.where("paymentType", "==", "rent")
					.where("createdAt", ">=", admin.firestore.Timestamp.fromDate(currentMonthStart))
					.where("createdAt", "<", admin.firestore.Timestamp.fromDate(nextMonthStart))
					.limit(1)
					.get();

				if (!rentPaidSnapshot.empty) {
					logger.info(`Rent already paid for seeker ${seekerId} for property ${propertyId} this month. Skipping.`);
					continue;
				}

				
				const userDoc = await db.collection("users").doc(seekerId).get();
				if (!userDoc.exists) {
					logger.warn(`User document for seeker ${seekerId} not found. Cannot send reminder.`);
					continue;
				}

				const fcmToken = userDoc.data()?.fcmToken;
				if (!fcmToken) {
					logger.warn(`FCM token not found for seeker ${seekerId}. Cannot send reminder.`);
					continue;
				}

				const notificationTitle = "Rent Payment Reminder 🏠";
				const notificationBody = `It's time to pay your monthly rent for ${roomName} at ${propertyName}.`;

				
				const message = {
					notification: {
						title: notificationTitle,
						body: notificationBody,
					},
					token: fcmToken,
					
					android: {
						priority: "high",
						notification: {
							icon: "launcher_icon.png",
							color: "#1565C0",
						},
					},
					apns: { payload: { aps: { sound: "default" } } },
				};

				try {
					await admin.messaging().send(message);
					logger.info(`Successfully sent rent reminder to seeker ${seekerId}`);

					
					await db.collection("users").doc(seekerId).collection("notifications").add({
						title: notificationTitle,
						body: notificationBody,
						createdAt: admin.firestore.FieldValue.serverTimestamp(),
						read: false,
						type: "rent_reminder",
						relatedId: bookingDoc.id,
					});

					remindersSent++;
				} catch (messagingError) {
					logger.error(`Failed to send rent reminder to seeker ${seekerId}:`, messagingError);
				}
			}
			logger.info(`Rent reminder job finished. Sent ${remindersSent} reminders.`);
		} catch (error) {
			logger.error("Error in sendMonthlyRentReminders job:", error);
		}
	});




export const requestWithdrawal = onCall(
	{ region: "us-central1" },
	async (request) => {
		const { amount: grossAmount, method } = request.data;
		const uid = request.auth?.uid;

		if (!uid) {
			throw new onCall.HttpsError("unauthenticated", "You must be logged in to request a withdrawal.");
		}

		if (!grossAmount || grossAmount <= 0 || !method) {
			throw new onCall.HttpsError("invalid-argument", "Missing required fields for withdrawal request.");
		}

		const walletRef = db.collection("wallets").doc(uid);
		const withdrawalsCol = db.collection("withdrawals");

		
		const now = new Date();
		const oneWeekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
		const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

		const weeklyWithdrawalsSnap = await withdrawalsCol
			.where("userId", "==", uid)
			.where("status", "in", ["pending", "completed"])
			.where("createdAt", ">=", admin.firestore.Timestamp.fromDate(oneWeekAgo))
			.get();

		const monthlyWithdrawalsSnap = await withdrawalsCol
			.where("userId", "==", uid)
			.where("status", "in", ["pending", "completed"])
			.where("createdAt", ">=", admin.firestore.Timestamp.fromDate(startOfMonth))
			.get();

		let weeklyTotal = 0;
		weeklyWithdrawalsSnap.forEach(doc => weeklyTotal += doc.data().amount);

		let monthlyTotal = 0;
		monthlyWithdrawalsSnap.forEach(doc => monthlyTotal += doc.data().amount);

		const WEEKLY_LIMIT = 100000 * 100;
		const MONTHLY_LIMIT = 400000 * 100;

		if (weeklyTotal + grossAmount > WEEKLY_LIMIT) {
			const remaining = (WEEKLY_LIMIT - weeklyTotal) / 100;
			throw new onCall.HttpsError("failed-precondition", `Weekly withdrawal limit of ₱100,000 exceeded. You can withdraw up to ₱${remaining.toFixed(2)} more this week.`);
		}

		if (monthlyTotal + grossAmount > MONTHLY_LIMIT) {
			const remaining = (MONTHLY_LIMIT - monthlyTotal) / 100;
			throw new onCall.HttpsError("failed-precondition", `Monthly withdrawal limit of ₱400,000 exceeded. You can withdraw up to ₱${remaining.toFixed(2)} more this month.`);
		}

		
		const serviceFee = Math.round(grossAmount * 0.05);
		const netAmount = grossAmount - serviceFee;

		
		const amountToDecrement = grossAmount;

		const withdrawalRef = db.collection("withdrawals").doc(); 

		try {
			await db.runTransaction(async (t) => {
				
				const userWalletRef = db.collection("wallets").doc(uid);
				const userRef = db.collection("users").doc(uid);
				const adminWalletRef = db.collection("wallets").doc(RUME_ADMIN_UID);

				const userWalletSnap = await t.get(userWalletRef);
				const userSnap = await t.get(userRef);
				const adminWalletSnap = await t.get(adminWalletRef);


				
				if (!userWalletSnap.exists) {
					throw new onCall.HttpsError("not-found", "Wallet not found.");
				}

				const currentBalance = userWalletSnap.data().amount || 0;
				if (currentBalance < amountToDecrement) {
					throw new onCall.HttpsError("failed-precondition", "Insufficient balance.");
				}

				const userName = userSnap.data()?.firstName || "Unknown";

			

				
				t.update(userWalletRef, {
					amount: admin.firestore.FieldValue.increment(-amountToDecrement),
					updatedAt: admin.firestore.FieldValue.serverTimestamp(),
				});

			
				t.set(withdrawalRef, {
					withdrawalId: withdrawalRef.id,
					userId: uid,
					userName: userName,
					amount: grossAmount,
					serviceFee: serviceFee,
					netAmount: netAmount,
					method: method,
					accountNumber: uid,
					status: "completed",
					createdAt: admin.firestore.FieldValue.serverTimestamp(),
					updatedAt: admin.firestore.FieldValue.serverTimestamp(),
				});

				
				const walletWithdrawalRef = userWalletRef.collection("withdrawals").doc(withdrawalRef.id);
				t.set(walletWithdrawalRef, {
					withdrawalId: withdrawalRef.id,
					amount: -amountToDecrement,
					serviceFee: serviceFee,
					netAmount: -netAmount, 
					paymentType: "withdrawal",
					status: "completed", 
					method: method,
					createdAt: admin.firestore.FieldValue.serverTimestamp(),
				});

			
				if (serviceFee > 0) {
					if (!adminWalletSnap.exists) {
						t.set(adminWalletRef, {
							userId: RUME_ADMIN_UID,
							amount: serviceFee,
							role: "admin",
							createdAt: admin.firestore.FieldValue.serverTimestamp(),
							updatedAt: admin.firestore.FieldValue.serverTimestamp(),
						});
					} else {
						t.update(adminWalletRef, {
							amount: admin.firestore.FieldValue.increment(serviceFee),
							updatedAt: admin.firestore.FieldValue.serverTimestamp(),
						});
					}

					
					const adminTransactionRef = adminWalletRef.collection("transactions").doc(withdrawalRef.id);
					t.set(adminTransactionRef, {
						transactionId: withdrawalRef.id,
						amount: serviceFee,
						paymentType: "commission_withdrawal", 
						status: "completed",
						description: `Commission from owner withdrawal.`,
						relatedUserId: uid,
						createdAt: admin.firestore.FieldValue.serverTimestamp(),
					});
				}
			});
			logger.info(`Withdrawal request ${withdrawalRef.id} for ₱${(grossAmount / 100).toFixed(2)} created for user ${uid}.`);

			
			const adminUserDoc = await db.collection("users").doc(RUME_ADMIN_UID).get();
			if (adminUserDoc.exists && adminUserDoc.data()?.fcmToken) {
				await admin.messaging().send({
					token: adminUserDoc.data().fcmToken,
					
					notification: {
						title: "Withdrawal Processed",
						body: `An owner has successfully withdrawn ₱${(grossAmount / 100).toFixed(2)}.`,
					},
				});
			}

			return {
				success: true,
				message: "Withdrawal successful! The amount has been processed.", 
			};
		} catch (error) {
			logger.error(`Error processing withdrawal for user ${uid}:`, error);
			if (error instanceof onCall.HttpsError) {
				throw error;
			}
			throw new onCall.HttpsError("internal", "An error occurred while processing your request.");
		}
	}
);

export const searchProperties = onCall(
	{ region: "us-central1", secrets: ["GEMINI_API_KEY", "PLACES_API_KEY"] },
	async (request) => {
		const query = request.data.query;
		if (!query) throw new Error("Missing query");

		return await searchPropertiesFlow({ query });
	}
);

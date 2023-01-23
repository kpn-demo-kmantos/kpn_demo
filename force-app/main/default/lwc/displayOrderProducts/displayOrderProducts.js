import { LightningElement, api, wire } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, subscribe, MessageContext } from "lightning/messageService";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import STATUS_FIELD from "@salesforce/schema/Order.Status";
import HANDLE_ORDER from "@salesforce/messageChannel/Handle_Order__c";
import getOrderProducts from "@salesforce/apex/OrderController.getOrderProducts";
import confirmOrder from "@salesforce/apex/OrderController.confirmOrder";

export default class DisplayOrderProducts extends LightningElement {
    @api
    recordId;

    errorMessage;
    products = [];
    allProducts = [];
    disableConfirmOrder;
    infiniteLoadOffset = 30;
    columns = [
        { label: "Name", fieldName: "ProductName" },
        {
            label: "Price",
            fieldName: "UnitPrice",
            type: "currency",
            cellAttributes: { alignment: "left" },
        },
        { label: "Quantity", fieldName: "Quantity" },
        {
            label: "Total Price",
            fieldName: "TotalPrice",
            type: "currency",
            cellAttributes: { alignment: "left" },
        },
    ];

    // Needed for our messaging channel to message between the 2 components.
    @wire(MessageContext)
    messageContext;

    @wire(getRecord, {
        recordId: "$recordId",
        fields: [STATUS_FIELD],
    })
    order({ error, data }) {
        if (data) {
            // If our Order is Activated then its no longer able to confirm Order for a second time.
            if (getFieldValue(data, STATUS_FIELD) === "Activated") {
                this.disableConfirmOrder = true;
            }
        } else if (error) {
            // Proper error handling
            this.errorMessage = `Couldn't fetch the Order.`;
            if (Array.isArray(error.body)) {
                this.errorMessage = error.body.map((e) => e.message).join(", ");
            } else if (typeof error.body.message === "string") {
                this.errorMessage = error.body.message;
            }
        }
    }

    connectedCallback() {
        // Get all Order products.
        this.orderProducts();
        // Subscribe to the message channel to be able to receive message from the other component
        // Alternatively the 2 componenets could be wrapped in a third parent component and communicate with each other using child-parent and parent-child communication.
        // Alternatively we could also use pubsub for communication.
        subscribe(this.messageContext, HANDLE_ORDER, (message) =>
            this.handleMessage(message)
        );
    }

    handleMessage(message) {
        // We received a signal that the order has updated Order Items and we need to refetch the Order Items.
        if (message.fetch) {
            // Get all Order products.
            this.orderProducts();
        }
    }

    async orderProducts() {
        this.errorMessage = undefined;
        // Get all Order products.
        const data = await getOrderProducts({ recordId: this.recordId });
        if (data) {
            if (!data?.length) {
                this.errorMessage = `Order is currently empty.`;
                return;
            }
            this.allProducts = JSON.parse(JSON.stringify(data));
            // This map needs to be done because datatable columns attribute understands up to 1 depth of childs.
            this.allProducts = this.allProducts.map((orderItem) => {
                orderItem.ProductName = orderItem.Product2.Name;

                return orderItem;
            });
            // Push the first products in the datatable, the rest of them will be loaded using infinite-load of datatable in order to handle big amounts of products (as exercise required).
            this.products = this.allProducts.slice(0, this.infiniteLoadOffset);
            // Enable infinite load in case the products added will make the datatable too long, otherwise datatable will itself deactivate this again.
            let datatable = this.template.querySelector(".orderItems");
            if (datatable) {
                datatable.enableInfiniteLoading = true;
            }
        } else {
            this.errorMessage = `Couldn't fetch any Products.`;
        }
    }

    async onConfirmOrderClickHandler() {
        // Informative message that the products were sent to the external system for confirmation.
        this.showToast(
            `Confirming ${this.allProducts.length} Product${
                this.allProducts.length === 1 ? "" : "s"
            }.`,
            `Waiting for confirmation of external system...`,
            "warning"
        );
        const success = await confirmOrder({
            orderId: this.recordId,
        });
        // We assume that if we get 200 response the confirmation was successful.
        if (success) {
            // Since its success then disable the confirm button and signal the change to the other component as well because now our Order is Activated.
            this.disableConfirmOrder = true;
            publish(this.messageContext, HANDLE_ORDER, { deactivate: true });
            this.showToast(
                `Success!`,
                `${this.allProducts.length} Product${
                    this.allProducts.length === 1 ? " was" : "s were"
                } confirmed!`,
                "success"
            );
            this.showToast(
                `Order Status`,
                `Order is now Activated and cannot be further edited!`,
                "success"
            );
        } else {
            this.showToast(
                `Error!`,
                `An error occured while confirming Products, please try again later!`,
                "error"
            );
        }
    }

    onLoadMoreDataHandler(event) {
        // Standard infinite load handler. If more products can be added the add them to the list of datatable otherwise stop the functionality of infinite load so it doesn't continue.
        event.target.isLoading = true;
        if (this.products.length >= this.allProducts.length) {
            event.target.enableInfiniteLoading = false;
        } else {
            this.products = this.products.concat(
                this.allProducts.slice(
                    this.products.length,
                    this.products.length + this.infiniteLoadOffset
                )
            );
        }
        event.target.isLoading = false;
    }

    showToast(title, message, variant) {
        // Reusable show toast
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
            })
        );
    }
}
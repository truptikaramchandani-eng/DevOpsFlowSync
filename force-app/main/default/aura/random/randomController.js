({
	increment : function(component, event, helper) {
        let val = component.get("v.count");
        component.set("v.count", val + 1);
    },

    decrement : function(component, event, helper) {
        let val = component.get("v.count");
        component.set("v.count", val - 1);
    }
})